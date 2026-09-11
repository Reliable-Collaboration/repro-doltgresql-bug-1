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
