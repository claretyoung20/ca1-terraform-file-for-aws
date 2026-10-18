# CA1 - The helper scripts, and how the Java apps get their settings

This file explains every script in `ca1-aws/`, and how the Product and Coupon apps on AWS get the settings from the `.env` file instead of the ones in `application.yml`. `README.md` has the one-line summary of each file; this is the long version.

**Contents**

1. [The big picture](#1-the-big-picture)
2. [How the Java app gets its settings from the env file](#2-how-the-java-app-gets-its-settings-from-the-env-file)
3. [`aws/` - setting up servers](#3-aws--setting-up-servers)
4. [`db/` - the database](#4-db--the-database)
5. [`k6/` - generating load](#5-k6--generating-load)
6. [`analysis/` and the experiment log](#6-analysis-and-the-experiment-log)
7. [The order of one experiment run](#7-the-order-of-one-experiment-run)

---

## 1. The big picture

| Folder | Runs on | Job |
| --- | --- | --- |
| `aws/` | Product and Coupon servers at first boot; the load generator once | Turns an empty Amazon Linux server into a running app, or into a load generator |
| `db/` | Load generator | Creates the tables once, and resets the product table before every run |
| `k6/` | Load generator | Sends the load and saves the raw results |
| `analysis/` | Load generator or your Mac | Turns raw results into tables and charts for the report |

Terraform uploads the whole folder to `s3://<bucket>/ca1-aws/`. The servers download what they need from there, so **after editing a script, run `terraform apply`** to upload the new version.

---

## 2. How the Java app gets its settings from the env file

**Short answer:** Spring Boot doesn't ignore `application.yml` (the services use `.yml`, not `.properties`, but the rule is the same). Environment variables have **higher priority** than it, so any setting given as an environment variable replaces the value in the file. Settings with no environment variable still come from the file; for example, `server.port: 9090` is only in `application.yml`.

It happens in three steps.

### Step 1 - User data writes the env file (at first boot)

`aws/product-userdata.sh` runs as root the first time the server starts. It reads the values from Parameter Store (allowed by the server's IAM role) and writes them to `/etc/productservice.env`:

```
SPRING_DATASOURCE_URL=jdbc:mysql://ca1-db.xxxx.eu-west-1.rds.amazonaws.com:3306/servicedb
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=<decrypted SecureString>
COUPONSERVICE_URL=http://10.0.x.x:9091/couponapi/coupons/
SPRING_JPA_HIBERNATE_DDL_AUTO=none
MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true
INSTANCE_ID=i-0abc...
INSTANCE_AZ=eu-west-1a
```

It then runs `chmod 600` on the file, so only root can read the password.

### Step 2 - systemd turns the file into real environment variables

The script also creates the service definition:

```ini
[Service]
User=app
EnvironmentFile=/etc/productservice.env
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar /opt/productservice/app.jar
```

systemd runs as root, so it can read the protected file. It sets every line as an environment variable of the Java process, then starts Java as the unprivileged `app` user. The effect is the same as typing:

```bash
export SPRING_DATASOURCE_URL=... SPRING_DATASOURCE_PASSWORD=... ; java -jar app.jar
```

### Step 3 - Spring Boot ranks environment variables above `application.yml`

Spring Boot's `Environment` is an **ordered list of property sources**. When the app asks for a property, the **first** source that has it wins. From highest priority to lowest, the ones that matter here are:

1. Command-line arguments (`--spring.datasource.url=...`)
2. Java system properties (`-Dspring.datasource.url=...`)
3. **OS environment variables** ← the env file ends up here
4. `application.yml` / `application.properties` inside the JAR ← your local-development defaults

**Relaxed binding** then maps each environment variable name to a property name: lowercase it and turn `_` into `.`. Dashes don't matter. So `SPRING_DATASOURCE_URL` becomes `spring.datasource.url`.

| Env var | Property it overrides | Value in `application.yml` | Why it's overridden on AWS |
| --- | --- | --- | --- |
| `SPRING_DATASOURCE_URL` | `spring.datasource.url` | `jdbc:mysql://localhost:3306/servicedb` | Point to RDS instead of your laptop |
| `SPRING_DATASOURCE_USERNAME` | `spring.datasource.username` | `root` | RDS user `admin` |
| `SPRING_DATASOURCE_PASSWORD` | `spring.datasource.password` | `root123@` | The real password from SSM, never stored in the JAR |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | `spring.jpa.hibernate.ddl-auto` | `update` | `none`: the tables come from `db/schema.sql`, so several Product servers starting at once never race to change them |
| `MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED` | `management.endpoint.health.probes.enabled` | *(not set)* | Turns on `/actuator/health/liveness`, which the target group's health check calls. Spring only switches it on automatically on Kubernetes. |
| `COUPONSERVICE_URL` (Product only) | `couponService.url` | `http://localhost:9091/couponapi/coupons/` | The coupon server's private IP |

Two variables don't go through Spring's property system at all:

- **`INSTANCE_ID`** is read directly with `System.getenv("INSTANCE_ID")` in `productservice/.../config/ServedByFilter.java`. The filter puts it in an `X-Served-By` header on every response. k6 counts that header, and `analyse.py` uses the counts to chart which server handled each request.
- **`INSTANCE_AZ`** isn't read by any code at the moment. It's there for your own reference.

**Why `COUPONSERVICE_URL` works with `@Value("${couponService.url}")`:** the camel-case name `couponService` isn't a valid name for Spring's relaxed binding, so that route finds nothing. Spring then falls back to its plain environment-variable lookup, which also tries the name uppercased with `.` changed to `_`. `couponService.url` becomes `COUPONSERVICE_URL`, which matches. Spring's documentation recommends lowercase kebab-case names in `@Value`, such as `coupon-service.url`, because those map to environment variables more reliably. The current code works, though.

**Why this design:** the same JAR runs unchanged on your laptop (using the `application.yml` defaults) and on AWS (using the env file). No secrets are stored in the JAR, the user-data script or S3.

**To check it on a running server** (Session Manager shell):

```bash
sudo cat /proc/$(pgrep -f app.jar)/environ | tr '\0' '\n' | grep -v PASSWORD
```

The Coupon Service works the same way: `aws/coupon-userdata.sh` writes `/etc/couponservice.env`, which has the same variables except `COUPONSERVICE_URL`.

---

## 3. `aws/` - setting up servers

### `product-userdata.sh` and `coupon-userdata.sh`

**Runs on:** every Product server (launched by the Auto Scaling group) and the Coupon server, once, at first boot, as root.

**How it gets there:** the user data in the launch template (`terraform/product.tf`) and on the Coupon instance (`terraform/coupon.tf`) is only a 2-line bootstrap. It downloads this script from S3 and runs it, so fixing a bug only needs a re-upload, not a new launch template.

**What it does, in order:**

1. Writes all output to `/var/log/ca1-userdata.log`. It uses `set -euo pipefail` (stop on any error) but **not** `set -x`, which would print the DB password to the log.
2. Installs Java 17 (`java-17-amazon-corretto-headless`).
3. Gets the instance ID and Availability Zone from the instance metadata service, using an IMDSv2 token.
4. Creates a no-login `app` user, and downloads the JAR from S3 to `/opt/<service>/app.jar`.
5. Reads `/ca1/db/host`, `/ca1/db/username` and `/ca1/db/password` (plus `/ca1/coupon/url` for Product) from Parameter Store, and writes the env file (section 2).
6. Creates and starts the systemd service. `Restart=on-failure` restarts the JVM if it crashes. `SuccessExitStatus=143` means a normal stop (SIGTERM) isn't counted as a failure.
7. Checks `http://localhost:<port>/actuator/health/liveness` every 2 seconds for up to 5 minutes.

**Startup evidence:** each stage writes a UTC timestamp to `/var/log/ca1-timing.log`. For example (illustrative times):

```
2026-09-30T15:02:11Z userdata-start
2026-09-30T15:02:31Z java-installed
2026-09-30T15:02:34Z jar-downloaded
2026-09-30T15:02:36Z service-started
2026-09-30T15:03:02Z app-healthy
```

That tells you how long a new server takes from launch to ready, which explains how quickly autoscaling can react.

The only differences between the two scripts are the JAR name, the port (9090 or 9091) and the `COUPONSERVICE_URL` line.

### `loadgen-setup.sh`

**Runs on:** the load generator, once, by hand in a Session Manager shell (as `ssm-user`, not root).

- Installs k6 from its official RPM repo. If that fails, it downloads the latest release from GitHub instead.
- Installs the Python libraries: `pymysql` and `cryptography` for `dbtool.py`, and `pandas` and `matplotlib` for `analyse.py`.
- Creates `~/results`.

It's run by hand, not as user data, because Session Manager logs you in as `ssm-user`, and everything should be installed in that user's home directory.

### `create-dashboard.sh`

**Superseded by `terraform/dashboard.tf`; kept for reference.** It looks up the ALB, target group and Coupon instance by name, then creates the `ca1-dashboard` CloudWatch dashboard with widgets for ALB requests, 5xx errors and p50/p95 latency; healthy and unhealthy targets; ASG capacity and CPU; Coupon CPU; and RDS CPU and connections. It's why the Coupon instance must be named exactly `ca1-coupon`.

---

## 4. `db/` - the database

### `dbtool.py`

**Runs on:** the load generator (it's the only machine with an app-free route to RDS, through `ca1-loadgen-sg`).

It reads the host, user and password from Parameter Store like the apps do, so no password is stored on disk. It connects to MySQL with TLS encryption; it doesn't check the RDS certificate, which is fine for a lab.

| Command | What it does | When |
| --- | --- | --- |
| `python3 dbtool.py init` | Runs `schema.sql`, then `seed-coupons.sql` | Once, before any app starts |
| `python3 dbtool.py reset` | Runs `reset-products.sql` | **Before every experiment run** |
| `python3 dbtool.py status` | Prints the product and coupon counts, `max_connections` and the connections open right now | Any time; `max_connections` goes in report section 4.5 |

It removes comment lines before splitting the SQL at `;`, because a `;` inside a comment used to break the schema script.

### `schema.sql`

Creates the `servicedb` database and the `coupon` and `product` tables, matching the JPA entities exactly. It's run once, which is why the apps can use `ddl-auto=none`. `IF NOT EXISTS` makes it safe to run again.

### `seed-coupons.sql`

Inserts 10 coupons, `SAVE5` to `SAVE50`, expiring 31/12/2027. `INSERT IGNORE` makes it safe to run again. The workload only uses these codes, because an unknown code makes Product return a 500 error. That would measure a bug, not load.

### `reset-products.sql`

Empties the `product` table and refills it with exactly 200 rows (`Product-1` to `Product-200`). `GET /products` returns the **whole table**, and every test run adds rows with `POST`. Without a reset, each run would start with a bigger table and get slower, so runs couldn't be compared.

---

## 5. `k6/` - generating load

### `workload.js`

The load test itself. The important ideas:

- **Fixed arrival rate (open model):** k6 starts new requests at a fixed rate whatever the server does. If the server slows down, k6 doesn't slow down with it, so an overloaded server shows up as **higher latency and errors**, not as quietly receiving less traffic. That's what makes runs with 1, 2 and 3 servers comparable.
- **Same request order every run:** every 10th request (`WRITE_RATIO=0.1`) is a `POST /productapi/products` with one of the 10 coupons; the rest are `GET /productapi/products`. The choice is based on the request number, not random.
- **Timeout:** a request slower than 10 seconds (`REQ_TIMEOUT`) counts as failed.
- **Which server answered:** it counts the `X-Served-By` response header per instance.

| Profile | Load | Used for |
| --- | --- | --- |
| `smoke` | 2 requests/s for 1 minute | Checking everything works |
| `step` | 10 → 25 → 50 → 75 → 100 requests/s, each held 3 minutes (`STEPS`, `STEP_DURATION`) | Finding the limit of 1, 2 or 3 servers |
| `surge` | `LOW_RATE` 5 min → `HIGH_RATE` 15 min → `LOW_RATE` 20 min | Triggering autoscaling up and back down |
| `steady` | `RATE` (30) for `DURATION` (10 min) | The failure test: kill an instance mid-run |

### `run.sh`

Runs one experiment and keeps everything about it together.

```bash
export BASE_URL=http://<alb-dns> BUCKET=<bucket>     # terraform output -raw loadgen_env_commands
./run.sh A-baseline-1i-r1 step
./run.sh D-elastic-r1 surge -e HIGH_RATE=80
```

1. Records the ASG's min/desired/max and instance count (this is why the IAM role needs `autoscaling:DescribeAutoScalingGroups`).
2. Runs k6 and saves to `~/results/<RUN_ID>/`:
   - `raw.csv.gz` - every request (for `analyse.py`)
   - `summary.json` - k6's end-of-run summary
   - `report.html` - k6's HTML dashboard
   - `console.txt` - the terminal output
   - `meta.txt` - run ID, profile, start/end time (UTC), ASG size
3. Adds one line to `~/results/run-log.csv`.
4. Syncs `~/results` to `s3://<bucket>/results` (this is why the role needs `s3:PutObject`), so results survive if the load generator is deleted.

---

## 6. `analysis/` and the experiment log

### `analyse.py`

Turns `raw.csv.gz` into report-ready tables and charts.

| Command | Output | Use it for |
| --- | --- | --- |
| `python3 analyse.py timeline ~/results/<RUN_ID>` | `timeline.csv`, `timeline.png`: 4 charts over time (throughput, p50/p95 latency, error %, requests per server) | Any run, especially the failure test and the surge. `--mark "180:instance terminated"` draws a line at that second. |
| `python3 analyse.py steps ~/results/<RUN_ID>` | `steps.csv`: one row per load step, with requested vs achieved rate, p50/p95/p99, error % and dropped requests | One `step` run. It ignores the first 30 seconds of each step while it settles. |
| `python3 analyse.py compare <run1> <run2> ... --labels ...` | `compare.csv`, `compare.png`: p95 latency, throughput and errors against load, one line per configuration | 1 vs 2 vs 3 servers on the same charts |

`--steps` and `--hold` must match the values the run used.

### `experiment-log.csv`

You fill this in by hand during experiments: one row per event, with the UTC time, run ID, what happened, where you saw it and notes. Delete the example rows first. It's the evidence for things the metrics can't show, like "terminated i-0abc at 10:03".

---

## 7. The order of one experiment run

1. `python3 ~/ca1-aws/db/dbtool.py reset` (the table goes back to 200 rows)
2. `~/ca1-aws/k6/run.sh <RUN_ID> <profile>`
3. Note events in `experiment-log.csv` while it runs
4. `python3 ~/ca1-aws/analysis/analyse.py timeline` or `steps` on the run folder
5. Screenshot `ca1-dashboard` for the same time window
