## Alibaba2 Runtime Images

Image build contexts used by the `alibaba2` runtime deployment.

- `moodle/`: Moodle 4.5 with selected plugins
- `pgbouncer/`: PgBouncer image for DB pooling

Example build commands:

```bash
docker build -t <registry>/moodle:v0.1 alibaba2/images/moodle
docker build -t <registry>/pgbouncer:v0.1 alibaba2/images/pgbouncer
```
