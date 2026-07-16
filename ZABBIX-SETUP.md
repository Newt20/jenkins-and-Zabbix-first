# Zabbix Monitoring Setup (EC2)

Stack: Zabbix Server 6.4 + PostgreSQL 15 + Web frontend + Agent, all via `docker-compose.yaml`.

## 1. Install Zabbix on the EC2

```bash
# on the EC2 (with docker + docker compose installed)
git clone <your-repo-url> && cd Module-3-deployment   # or scp docker-compose.yaml up
docker compose up -d
docker compose ps        # all 4 containers should be Up
```

Open the AWS Security Group for the EC2:

| Port | Purpose                | Source          |
|------|------------------------|-----------------|
| 8088 | Zabbix web frontend    | Your IP         |

(Ports 10050/10051 stay internal to the Docker network — no need to expose them.)

Login: `http://<EC2-public-IP>:8088` — username `Admin`, password `zabbix` (change it after first login).

## 2. Add the EC2 as a host

1. **Data collection → Hosts → Create host**
2. Host name: `EC2-Instance` (must match `ZBX_HOSTNAME` in docker-compose.yaml)
3. Host groups: `Linux servers`
4. Interfaces → Add → **Agent**: DNS name `zabbix-agent`, Connect to **DNS**, port `10050`
5. Templates: link **Linux by Zabbix agent**
6. Save. Within ~1 minute the **ZBX** availability icon on the host should turn green.

## 3. CPU & memory monitoring

The **Linux by Zabbix agent** template already collects these — verify under
**Monitoring → Latest data** (filter host `EC2-Instance`):

- **CPU utilization** — item key `system.cpu.util`
- **Memory utilization** — item key `vm.memory.utilization`
- (plus load average, available memory, etc.)

The agent runs with `pid: host` + `privileged`, so these values are the EC2
machine's metrics, not the container's.

## 4. Alert trigger: CPU > 80%

1. **Data collection → Hosts → EC2-Instance → Triggers → Create trigger**
2. Name: `High CPU utilization (>80%)`
3. Severity: **High**
4. Expression:

   ```
   avg(/EC2-Instance/system.cpu.util,5m)>80
   ```

   (fires when average CPU over the last 5 minutes exceeds 80%)
5. Save.

Optional memory trigger:

```
avg(/EC2-Instance/vm.memory.utilization,5m)>90
```

## 5. Viewing the monitoring graphs

The **Linux by Zabbix agent** template ships with prebuilt graphs — no setup needed:

- **Monitoring → Hosts** → find `EC2-Instance` → click **Graphs** on that row.
  Available charts: CPU utilization, CPU usage, Memory utilization, Memory
  usage, System load, Swap usage.
- **Monitoring → Latest data** → filter host `EC2-Instance` → tick
  *CPU utilization* and *Memory utilization* → **Display graph** to plot them
  together ad hoc.

Graphs plot history, so allow 10–15 minutes of data collection after setup,
and set the time range picker (top right) to **Last 1 hour** so the data
isn't squashed.

> Note: the built-in **Zabbix server** host may show as unavailable (red ZBX
> icon). That default host points to `127.0.0.1:10050`, where no agent runs
> inside the server container. It's harmless — disable it under
> **Data collection → Hosts** if you want a clean list.

## 6. Building a dashboard

1. **Dashboards → All dashboards → Create dashboard**, name it `EC2 Monitoring`.
2. **Add widget** → type **Graph**:
   - In the **Data set**, set *host pattern* to `EC2-Instance` (pick it from
     the autocomplete dropdown — the field matches the host's **visible
     name**, and wildcards like `EC2*` also work).
   - Set *item pattern* to `CPU utilization`.
3. Add a second **Graph** widget the same way with item pattern
   `Memory utilization` (or use `*utilization` in one widget to plot CPU and
   memory on the same chart).
4. Optional widgets:
   - **Gauge** — live CPU %, using item *CPU utilization*.
   - **Problems** — shows the CPU > 80% trigger when it fires.
5. Click **Save changes** (top right).

If a widget shows "No data": the usual cause is a typo in the pattern —
fields are exact-match unless you add `*`, so pick values from the
autocomplete dropdown.

## 7. Test the trigger

```bash
# on the EC2 — burn CPU for 6 minutes
sudo apt install -y stress
stress --cpu $(nproc) --timeout 360
```

Watch **Monitoring → Problems** — the `High CPU utilization (>80%)` problem
should appear after ~5 minutes and resolve itself once the stress run ends.
