CREATE OR REPLACE FUNCTION transaction_first_activity(id VARCHAR(10), before_after CHAR(1)) RETURNS TABLE (trndate DATE, trntime TIME) AS $$
BEGIN
RETURN QUERY SELECT S.trndate, S.trntime
FROM trn_src_des AS S,
    (
        SELECT *
        FROM trn_src_des
        WHERE voucherid = id
    ) AS T
WHERE
CASE
    WHEN before_after = 'B' THEN
    s.desdep = t.sourcedep
    AND (s.trndate < t.trndate
    OR (s.trndate = t.trndate
    AND s.trntime <= t.trntime))
    WHEN before_after = 'A' THEN
    s.sourcedep = t.desdep
    AND (s.trndate > t.trndate
    OR (s.trndate = t.trndate
    AND s.trntime >= t.trntime))
END
ORDER BY
CASE WHEN before_after = 'A' THEN S.trndate END ASC,
CASE WHEN before_after = 'A' THEN S.trntime END ASC,
CASE WHEN before_after = 'B' THEN S.trndate END DESC,
CASE WHEN before_after = 'B' THEN S.trntime END DESC
LIMIT 1;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION is_deposit_registered_in_bank(id int) RETURNS bool AS $$
BEGIN
IF EXISTS (SELECT * FROM deposit WHERE dep_id = id) THEN RETURN true;
ELSE RETURN FALSE;
END IF;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION get_related_transactions(id VARCHAR(10), before_after CHAR(1)) RETURNS TABLE (voucherid VARCHAR(10),
                                                                                                        trndate DATE, trntime TIME,
                                                                                                        amount BIGINT, sourcedep INT,
                                                                                                        desdep INT, branch_id INT, 
                                                                                                        trn_desc VARCHAR(255)) AS $$
DECLARE sum INT;
DECLARE original_transaction RECORD;
DECLARE row RECORD;
BEGIN
    sum := 0;
    SELECT trn_src_des.* INTO original_transaction FROM trn_src_des WHERE trn_src_des.voucherid = id;
	CREATE TEMP TABLE first_day_transactions AS
    (SELECT S.*
    FROM
    trn_src_des AS S,
    (SELECT * from transaction_first_activity(id,before_after)) AS activity
    WHERE
		CASE
		WHEN before_after = 'B' THEN
		S.desdep = original_transaction.sourcedep
		WHEN before_after = 'A' THEN
		S.sourcedep = original_transaction.desdep
		END
        AND S.trndate = activity.trndate);
	RETURN QUERY SELECT * FROM first_day_transactions;
	sum := sum + (SELECT SUM(F.amount) FROM first_day_transactions AS F WHERE F.amount<>original_transaction.amount);
	DROP TABLE first_day_transactions;
    FOR row IN SELECT S.*
    FROM
    trn_src_des AS S,
    (SELECT * from transaction_first_activity(id,before_after)) AS activity
	WHERE
    CASE
	WHEN before_after = 'B' THEN
	(s.desdep = original_transaction.sourcedep
	AND S.trndate < activity.trndate)
	WHEN before_after = 'A' THEN
	(S.sourcedep = original_transaction.desdep
	AND S.trndate > activity.trndate)
	END
    ORDER BY
    CASE WHEN before_after = 'B' THEN S.trndate END DESC,
    CASE WHEN before_after = 'B' THEN S.trntime END DESC,
    CASE WHEN before_after = 'A' THEN S.trndate END ASC,
    CASE WHEN before_after = 'A' THEN S.trntime END ASC
    LOOP
    IF sum + row.amount <= original_transaction.amount*1.1
    THEN
        voucherid := row.voucherid;
        trndate := row.trndate;
        trntime := row.trntime;
        amount := row.amount;
        sourcedep := row.sourcedep;
        desdep := row.desdep;
        branch_id := row.branch_id;
        trn_desc := row.trn_desc;
        sum := sum + row.amount;
        RETURN NEXT;
    ELSE EXIT;
    END IF;
    END LOOP;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION get_all_related_transactions(id VARCHAR(10), before_after CHAR(1)) RETURNS TABLE (voucherid VARCHAR(10),
                                                                                                            trndate DATE, trntime TIME,
                                                                                                            amount BIGINT, sourcedep INT,
                                                                                                            desdep INT, branch_id INT, trn_desc VARCHAR(255)) AS $$
DECLARE row RECORD;
BEGIN
    FOR row IN SELECT *
        FROM get_related_transactions(id,before_after)
    LOOP
    IF before_after = 'B' AND row.sourcedep IS NOT NULL AND is_deposit_registered_in_bank(row.sourcedep) THEN
        RETURN QUERY SELECT * FROM get_all_related_transactions(row.voucherid,before_after);
    END IF;
	IF before_after = 'A' AND row.desdep IS NOT NULL AND is_deposit_registered_in_bank(row.desdep) THEN
        RETURN QUERY SELECT * FROM get_all_related_transactions(row.voucherid,before_after);
    END IF;
	voucherid := row.voucherid;
    trndate := row.trndate;
    trntime := row.trntime;
    amount := row.amount;
    sourcedep := row.sourcedep;
    desdep := row.desdep;
    branch_id := row.branch_id;
    trn_desc := row.trn_desc;
    RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION trace_transaction(id VARCHAR(10)) RETURNS TABLE (voucherid VARCHAR(10),
                                                                            trndate DATE, trntime TIME,
                                                                            amount BIGINT, sourcedep INT,
                                                                            desdep INT, branch_id INT, trn_desc VARCHAR(255)) AS $$
BEGIN
    RETURN QUERY SELECT * FROM (
    (SELECT * FROM trn_src_des WHERE trn_src_des.voucherid = id)
    UNION
    (SELECT *
    FROM
    get_all_related_transactions(id,'B'))
    UNION
	(SELECT *
    FROM
    get_all_related_transactions(id,'A')))
    AS trace ORDER BY trace.trndate ASC, trace.trntime ASC;
END;
$$ LANGUAGE PLPGSQL;