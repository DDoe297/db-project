CREATE VIEW check_national_code AS WITH code_formula AS
  (SELECT MOD((
            CAST(SUBSTRING(NatCod, 1, 1) AS INT) * 10 + 
            CAST(SUBSTRING(NatCod, 2, 1) AS INT) * 9 +
            CAST(SUBSTRING(NatCod, 3, 1) AS INT) * 8 +
            CAST(SUBSTRING(NatCod, 4, 1) AS INT) * 7 +
            CAST(SUBSTRING(NatCod, 5, 1) AS INT) * 6 +
            CAST(SUBSTRING(NatCod, 6, 1) AS INT) * 5 +
            CAST(SUBSTRING(NatCod, 7, 1) AS INT) * 4 +
            CAST(SUBSTRING(NatCod, 8, 1) AS INT) * 3 +
            CAST(SUBSTRING(NatCod, 9, 1) AS INT) * 2), 11) AS code_check,
          CID
   FROM customer)
SELECT (CASE
            WHEN c.code_check < 2 THEN CAST(SUBSTRING(NatCod, 10, 1) AS INT) = c.code_check
            ELSE CAST(SUBSTRING(NatCod, 10, 1) AS INT) = 11 - c.code_check
        END) AS is_national_code_correct,
       customer.*
FROM customer,
     code_formula AS c
WHERE c.CID = customer.CID;