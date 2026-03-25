-- Data exploaration
-- checking tables
SELECT COUNT(*) FROM staging.stg_contracts;
SELECT COUNT(*) FROM staging.stg_credit_applications;
SELECT COUNT(*) FROM staging.stg_interest_rate_rules;
SELECT COUNT(*) FROM staging.stg_compensation_fee_rules;

-- see head
SELECT * FROM staging.stg_contracts LIMIT 10;
SELECT * FROM staging.stg_credit_applications LIMIT 10;
SELECT * FROM staging.stg_interest_rate_rules LIMIT 10;
SELECT * FROM staging.stg_compensation_fee_rules LIMIT 10;

--check isnull
SELECT 
    COUNT(*) - COUNT(country) AS null_country,
    COUNT(*) - COUNT(currency) AS null_currency,
    COUNT(*) - COUNT(amount) AS null_amount,
    COUNT(*) - COUNT(contractual_term_in_months) AS null_term,
    COUNT(*) - COUNT(contract_id) AS null_contract_id
FROM staging.stg_contracts;

SELECT 
    COUNT(*) - COUNT(created_at) AS null_created_at,
    COUNT(*) - COUNT(partner_id) AS null_partner_id,
    COUNT(*) - COUNT(product_category) AS null_product_category,
    COUNT(*) - COUNT(country) AS null_country,
    COUNT(*) - COUNT(contract_id) AS null_contract_id,
    COUNT(*) - COUNT(credit_application_id) AS null_credit_application_id,
    COUNT(*) - COUNT(application_status) AS null_status
FROM staging.stg_credit_applications;

SELECT 
    COUNT(*) - COUNT(country) AS null_country,
    COUNT(*) - COUNT(product) AS null_product,
    COUNT(*) - COUNT(lower_bracket_amount) AS null_lower,
    COUNT(*) - COUNT(upper_bracket_amount) AS null_upper,
    COUNT(*) - COUNT(interest_rate) AS null_rate
FROM staging.stg_interest_rate_rules;

SELECT 
    COUNT(*) - COUNT(country) AS null_country,
    COUNT(*) - COUNT(product_category) AS null_product_category,
    COUNT(*) - COUNT(compensation_fee_rules) AS null_rules
FROM staging.stg_compensation_fee_rules;


-- Amount distribution of contract 
SELECT 
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	ROUND(AVG(amount), 2) AS avg_amount,
	ROUND(STDDEV(amount), 2) AS std_dev	
FROM staging.stg_contracts;

-- Contracts by country
SELECT country, COUNT(*) AS total_contract
FROM staging.stg_contracts
GROUP BY country

-- applications by contry and status
SELECT country, application_status, COUNT(*) AS total
FROM staging.stg_credit_applications
GROUP BY country, application_status

-- How many applications became contracts
SELECT 
    application_status,
    COUNT(*) AS total,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM staging.stg_credit_applications
GROUP BY application_status

-- products by country

SELECT country, product, COUNT(*) AS brackets
FROM staging.stg_interest_rate_rules
GROUP BY country, product

-- create the reporting 


CREATE TABLE reporting.contract_profitability (
    contract_id          VARCHAR(50),
    country_id           INTEGER,
    partner_id           INTEGER,
    product_category_id  INTEGER,
    amount               NUMERIC,
    term_in_months       INTEGER,
    interest_rate        NUMERIC,
    compensation_fee_pct NUMERIC,
    total_interest       NUMERIC,
    compensation_fee_amt NUMERIC,
    profit               NUMERIC,
    created_at           DATE,
    PRIMARY KEY (contract_id, country_id)
);


--- partner monthly metrics

CREATE TABLE reporting.partner_monthly_metrics AS
SELECT 
    fa.partner_id,
    fa.country_id,
    fa.product_category_id,
    DATE_TRUNC('month', fa.created_at) AS month,
    COUNT(*) AS total_applications,
    SUM(CASE WHEN fa.application_status = 'APPROVED' THEN 1 ELSE 0 END) AS approved_applications,
    ROUND(
        SUM(CASE WHEN fa.application_status = 'APPROVED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    ) AS approval_rate,
    SUM(fc.amount) AS total_contract_amount,
    AVG(fc.amount) AS avg_contract_amount,
    RANK() OVER (
        PARTITION BY fa.country_id, fa.product_category_id, DATE_TRUNC('month', fa.created_at)
        ORDER BY SUM(fc.amount) DESC
    ) AS amount_rank
FROM edw.fact_credit_applications fa
LEFT JOIN edw.fact_contracts fc 
    ON fa.contract_id = fc.contract_id 
    AND fa.country_id = fc.country_id
GROUP BY 
    fa.partner_id,
    fa.country_id,
    fa.product_category_id,
    DATE_TRUNC('month', fa.created_at);

SELECT COUNT(*) FROM reporting.partner_monthly_metrics;

SELECT 
    MIN(approval_rate) AS min_rate,
    MAX(approval_rate) AS max_rate,
    ROUND(AVG(approval_rate), 2) AS avg_rate
FROM reporting.partner_monthly_metrics;



--- assign the fees



CREATE TABLE reporting.compensation_fee_assignment AS

SELECT 
    pmm.partner_id,
    pmm.country_id,
    pmm.product_category_id,
    pmm.month,
    dc.country_code,
    dpc.product_category_name,
    pmm.total_contract_amount,
    pmm.avg_contract_amount,
    pmm.approval_rate,
    pmm.amount_rank,

    CASE
        WHEN dpc.product_category_name = 'Car Finance' AND dc.country_code = 'LT' AND pmm.avg_contract_amount >= 7500 THEN 0.07
        WHEN dpc.product_category_name = 'Car Finance' AND dc.country_code = 'EE' AND pmm.avg_contract_amount >= 7500 THEN 0.07
        WHEN dpc.product_category_name = 'Car Finance' AND dc.country_code = 'LV' AND pmm.avg_contract_amount >= 6000 THEN 0.07
        WHEN dpc.product_category_name = 'Car Finance' AND dc.country_code = 'PL' AND pmm.avg_contract_amount >= 8000 THEN 0.07
        WHEN dpc.product_category_name = 'Car Finance' AND dc.country_code = 'CZ' AND pmm.avg_contract_amount >= 5500 THEN 0.07
        WHEN dpc.product_category_name = 'Green' AND pmm.amount_rank = 1 THEN 0.06
        WHEN dpc.product_category_name = 'Hire Purchase' AND dc.country_code = 'LT' AND pmm.total_contract_amount > 20000 AND pmm.approval_rate > 40 THEN 0.09
        WHEN dpc.product_category_name = 'Hire Purchase' AND dc.country_code = 'EE' AND pmm.total_contract_amount > 70000 AND pmm.approval_rate > 55 THEN 0.075
        WHEN dpc.product_category_name = 'Personal Loan' AND dc.country_code = 'LT' AND pmm.total_contract_amount > 5000 THEN 0.035
        WHEN dpc.product_category_name = 'Personal Loan' AND dc.country_code = 'EE' AND pmm.total_contract_amount > 5000 THEN 0.035
        WHEN dpc.product_category_name = 'Personal Loan' AND dc.country_code = 'LV' AND pmm.total_contract_amount > 5000 THEN 0.035
        WHEN dpc.product_category_name = 'Personal Loan' AND dc.country_code = 'PL' AND pmm.total_contract_amount > 50000 THEN 0.045
        WHEN dpc.product_category_name = 'Personal Loan' AND dc.country_code = 'CZ' AND pmm.total_contract_amount > 75000 THEN 0.065
        ELSE 0
    END AS compensation_fee_pct

FROM reporting.partner_monthly_metrics pmm
JOIN edw.dim_country dc ON pmm.country_id = dc.country_id
JOIN edw.dim_product_category dpc ON pmm.product_category_id = dpc.product_category_id;


-- how many partners got a fee vs 0
SELECT 
    compensation_fee_pct,
    COUNT(*) AS total
FROM reporting.compensation_fee_assignment
GROUP BY compensation_fee_pct
ORDER BY compensation_fee_pct DESC;



--- create contract_profitability 

CREATE TABLE reporting.contract_profitability AS
SELECT
    fc.contract_id,
    fc.country_id,
    dc.country_code,
    fa.partner_id,
    fa.product_category_id,
    dpc.product_category_name,
    fc.amount,
    fc.term_in_months,
    fa.created_at,
    DATE_TRUNC('month', fa.created_at) AS contract_month,
    irr.interest_rate,
    COALESCE(cfa.compensation_fee_pct, 0) AS compensation_fee_pct,
    ROUND(
        fc.amount * (irr.interest_rate / 12) / (1 - POWER(1 + irr.interest_rate / 12, -fc.term_in_months)),
        2
    ) AS monthly_payment,
    ROUND(
        fc.amount * (irr.interest_rate / 12) / (1 - POWER(1 + irr.interest_rate / 12, -fc.term_in_months)) * fc.term_in_months - fc.amount,
        2
    ) AS total_interest,
    ROUND(fc.amount * COALESCE(cfa.compensation_fee_pct, 0), 2) AS compensation_fee_amt,
    ROUND(
        fc.amount * (irr.interest_rate / 12) / (1 - POWER(1 + irr.interest_rate / 12, -fc.term_in_months)) * fc.term_in_months - fc.amount
        - fc.amount * COALESCE(cfa.compensation_fee_pct, 0),
        2
    ) AS profit
FROM edw.fact_contracts fc
JOIN edw.dim_country dc 
    ON fc.country_id = dc.country_id
JOIN edw.fact_credit_applications fa 
    ON fc.contract_id = fa.contract_id 
    AND fc.country_id = fa.country_id
JOIN edw.dim_product_category dpc 
    ON fa.product_category_id = dpc.product_category_id
JOIN staging.stg_interest_rate_rules irr
    ON dc.country_code = irr.country
    AND dpc.product_category_name = irr.product
    AND fc.amount >= irr.lower_bracket_amount
    AND (fc.amount <= irr.upper_bracket_amount OR irr.upper_bracket_amount IS NULL)
LEFT JOIN reporting.compensation_fee_assignment cfa
    ON fa.partner_id = cfa.partner_id
    AND fa.country_id = cfa.country_id
    AND fa.product_category_id = cfa.product_category_id
    AND DATE_TRUNC('month', fa.created_at) = cfa.month
WHERE fc.term_in_months > 0 
AND fc.term_in_months IS NOT NULL;

-- contracts with term being 0
-- save excluded contracts for documentation
CREATE TABLE reporting.excluded_contracts AS
SELECT 
    fc.contract_id,
    dc.country_code,
    fc.amount,
    fc.term_in_months,
    'Zero or NULL term in months' AS exclusion_reason
FROM edw.fact_contracts fc
JOIN edw.dim_country dc ON fc.country_id = dc.country_id
WHERE fc.term_in_months = 0 OR fc.term_in_months IS NULL;


SELECT COUNT(*) FROM reporting.contract_profitability;


---analysis

-- total contracts, revenue and profit by country
SELECT 
    country_code,
    COUNT(*) AS total_contracts,
    ROUND(SUM(amount), 2) AS total_loan_amount,
    ROUND(SUM(total_interest), 2) AS total_interest_earned,
    ROUND(SUM(compensation_fee_amt), 2) AS total_compensation_paid,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(interest_rate) * 100, 2) AS avg_interest_rate_pct,
    ROUND(SUM(profit) / SUM(total_interest) * 100, 2) AS profit_margin_pct
FROM reporting.contract_profitability
GROUP BY country_code
ORDER BY total_profit DESC;

--- product category

SELECT 
    product_category_name,
    COUNT(*) AS total_contracts,
    ROUND(SUM(amount), 2) AS total_loan_amount,
    ROUND(SUM(total_interest), 2) AS total_interest_earned,
    ROUND(SUM(compensation_fee_amt), 2) AS total_compensation_paid,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(interest_rate) * 100, 2) AS avg_interest_rate_pct,
    ROUND(SUM(profit) / SUM(total_interest) * 100, 2) AS profit_margin_pct
FROM reporting.contract_profitability
GROUP BY product_category_name
ORDER BY total_profit DESC;



---partner
SELECT 
    cp.country_code,
    cp.partner_id,
    COUNT(*) AS total_contracts,
    ROUND(SUM(amount), 2) AS total_loan_amount,
    ROUND(SUM(total_interest), 2) AS total_interest_earned,
    ROUND(SUM(compensation_fee_amt), 2) AS total_compensation_paid,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(profit) / SUM(total_interest) * 100, 2) AS profit_margin_pct
FROM reporting.contract_profitability cp
GROUP BY cp.country_code, cp.partner_id
ORDER BY total_profit DESC
;

SELECT 
    cp.country_code || ' - ' || cp.partner_id::text AS partner_label,
    COUNT(*) AS total_contracts,
    ROUND(SUM(amount), 2) AS total_loan_amount,
    ROUND(SUM(total_interest), 2) AS total_interest_earned,
    ROUND(SUM(compensation_fee_amt), 2) AS total_compensation_paid,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(SUM(profit) / SUM(total_interest) * 100, 2) AS profit_margin_pct
FROM reporting.contract_profitability cp
GROUP BY cp.country_code, cp.partner_id
ORDER BY total_profit DESC