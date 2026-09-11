# DoltgreSQL 1.3.1: after an ALTER TABLE, a table with a generated `COALESCE` column refuses inserts

On DoltgreSQL 1.3.1, a table with a `STORED` generated column whose expression is `COALESCE` over an
expression, such as `COALESCE(a + 1, 0)`, accepts inserts until the table is altered. After one
`ALTER TABLE t ADD PRIMARY KEY (a)`, every `INSERT` into the table fails:

```
ERROR:  Invalid default value for '(coalesce("a" + 1 as a + 1,0))': at or near "as": syntax error
```

PostgreSQL 18.6 runs the same statements without an error.

Reported upstream: https://github.com/dolthub/doltgresql/issues/3323

## Reproduce it

You need Docker and a POSIX shell: Linux, macOS, or Windows with WSL. The first run downloads the image.

```sh
git clone https://github.com/Reliable-Collaboration/repro-doltgresql-bug-1.git
cd repro-doltgresql-bug-1
./repro.sh            # DoltgreSQL 1.3.1: shows the error, exits 1
./repro.sh postgres   # PostgreSQL 18.6: the expected behavior, exits 0
```

`repro.sh` starts a throwaway server container, waits until it accepts connections, runs
[`repro.sql`](repro.sql) with the `psql` client inside that container, prints the output, and removes
the container.

To try another DoltgreSQL release, name its image:

```sh
DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
```

### Without the script

The same steps by hand, from the repository directory:

```sh
docker run -d --name doltgresql-bug-1 -e DOLTGRES_PASSWORD=password dolthub/doltgresql:1.3.1
docker cp repro.sql doltgresql-bug-1:/tmp/repro.sql
docker exec -t -e PGPASSWORD=password doltgresql-bug-1 psql -X -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql
docker rm -f doltgresql-bug-1
```

If `docker exec` answers that the connection was refused, the server is still starting: wait a few
seconds and run it again.

## The test

[`repro.sql`](repro.sql):

```sql
-- A table with a stored generated column that uses COALESCE over an expression.
CREATE TABLE t (
    a int NOT NULL,
    b int GENERATED ALWAYS AS (COALESCE(a + 1, 0)) STORED
);

-- Before the table is altered, an insert works.
INSERT INTO t (a) VALUES (1);

-- Alter the table once: add its primary key.
ALTER TABLE t ADD PRIMARY KEY (a);

-- The same insert again, with the next value.
INSERT INTO t (a) VALUES (2);

SELECT * FROM t ORDER BY a;
```

## Expected behavior

Both inserts succeed, and the table holds two rows. This is what PostgreSQL 18.6 does
(`./repro.sh postgres`):

```
Starting postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af
Running repro.sql

-- A table with a stored generated column that uses COALESCE over an expression.
CREATE TABLE t (
    a int NOT NULL,
    b int GENERATED ALWAYS AS (COALESCE(a + 1, 0)) STORED
);
CREATE TABLE
-- Before the table is altered, an insert works.
INSERT INTO t (a) VALUES (1);
INSERT 0 1
-- Alter the table once: add its primary key.
ALTER TABLE t ADD PRIMARY KEY (a);
ALTER TABLE
-- The same insert again, with the next value.
INSERT INTO t (a) VALUES (2);
INSERT 0 1
SELECT * FROM t ORDER BY a;
 a | b 
---+---
 1 | 2
 2 | 3
(2 rows)

Result: no errors.
```

## Actual behavior

The `ALTER TABLE` succeeds, but the second `INSERT` fails, and the table still holds only the first row.
This is what DoltgreSQL 1.3.1 does (`./repro.sh`):

```
Starting dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851
Running repro.sql

-- A table with a stored generated column that uses COALESCE over an expression.
CREATE TABLE t (
    a int NOT NULL,
    b int GENERATED ALWAYS AS (COALESCE(a + 1, 0)) STORED
);
CREATE TABLE
-- Before the table is altered, an insert works.
INSERT INTO t (a) VALUES (1);
INSERT 0 1
-- Alter the table once: add its primary key.
ALTER TABLE t ADD PRIMARY KEY (a);
ALTER TABLE
-- The same insert again, with the next value.
INSERT INTO t (a) VALUES (2);
psql:/tmp/repro.sql:14: ERROR:  Invalid default value for '(coalesce("a" + 1 as a + 1,0))': at or near "as": syntax error
SELECT * FROM t ORDER BY a;
 a | b 
---+---
 1 | 2
(1 row)

Result: the server answered with 1 error(s).
```

## Other observations

Each was checked on DoltgreSQL 1.3.1 by editing `repro.sql` and running `./repro.sh` again:

- After the alteration, every `INSERT` fails with the same error, and so do `UPDATE` and `CREATE INDEX`
  on the table. `SELECT` still works.
- Adding a unique constraint, dropping a column, or changing a column's type has the same effect as
  adding the primary key. Adding a column, or creating an index, as the only alteration does not.
- `COALESCE(abs(a), 0)` triggers it too. `COALESCE(a, 0)` does not, and neither does `a + 1` without
  `COALESCE`.
- Declaring the primary key inside `CREATE TABLE`, instead of adding it afterwards, avoids the error.
- Possibly related: [dolthub/doltgresql#810](https://github.com/dolthub/doltgresql/issues/810).

## Environment

- DoltgreSQL 1.3.1, the newest release when this was written: image `dolthub/doltgresql:1.3.1`, digest
  `sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851`, built for linux/amd64 and
  linux/arm64. Its bundled `psql` is 17.11.
- PostgreSQL 18.6: image `postgres:18.6-bookworm`, digest
  `sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af`.
- Reproduced on 2026-09-11 with Docker 29.7.2 on Linux x86_64.
