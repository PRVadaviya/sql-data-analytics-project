

-- STEP 7: CHANGE OVER TIME TRENDS 

-- ANALYZE SALES PERFORMANCE OVER TIME 

	SELECT 
		--YEAR(order_date) AS ORDER_YEAR,
		MONTH(order_date) AS ORDER_YEAR,
		SUM(sales_amount) AS TOTAL_SALES,
		COUNT(customer_key) AS TOTAL_CUSTOMER,
		SUM(quantity) AS TOTAL_QUANTITY
	FROM GOLD.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY MONTH(order_date)
	ORDER BY MONTH(order_date)
	--GROUP BY YEAR(order_date)
	--ORDER BY YEAR(order_date)


	--USING DATETRUNC FUNCTION

	SELECT 
		--YEAR(order_date) AS ORDER_YEAR,
		DATETRUNC(YEAR,order_date) AS ORDER_YEAR,
		SUM(sales_amount) AS TOTAL_SALES,
		COUNT(customer_key) AS TOTAL_CUSTOMER,
		SUM(quantity) AS TOTAL_QUANTITY
	FROM GOLD.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(YEAR,order_date)
	ORDER BY DATETRUNC(YEAR,order_date)


-- STEP 8 : CUMULATIVE ANALYSIS
-- AGGREGATE THE DATA PROGRESSIVELY OVER TIME
-- HELPS TO UNDERSTAND WHETHER OUR BUSINESS IS GROWING OR DECLINING
-- E [CUMULATIVE MEASURE] BY [DATE DIMENSION]
-- RUNNING TOTAL SALES BY YEAR , MOVING AVERAGE OF SALES BY MONTH

-- CALCULATE THE TOTAL SALES PER MONTH AND THE RUNNING TOTAL OF SALES OVER TIME


	SELECT
		ORDER_DATE,
		TOTAL_SALES,
		SUM(TOTAL_SALES) OVER(PARTITION BY ORDER_DATE ORDER BY ORDER_DATE) AS RUNNING_TOTAL_SALES,
		AVG(AVG_PRICE) OVER(PARTITION BY ORDER_DATE ORDER BY ORDER_DATE) AS MOVING_PRICE
	FROM (
		SELECT 
			DATETRUNC(MONTH,order_date) AS ORDER_DATE,
			SUM(sales_amount) AS TOTAL_SALES,
			AVG(price) AS AVG_PRICE
		FROM GOLD.fact_sales
		WHERE order_date IS NOT NULL
		GROUP BY DATETRUNC(MONTH,order_date)
		)T
	ORDER BY DATETRUNC(MONTH,order_date)

--STEP 9: PERFORMANCE ANALYSIS

-- COMPARING THE CURRENT VALUE TO A TARGET VALUE
-- HELPS MEASURE SUCCESS AND COMPAPRE PERFORMANCE
-- CURRENT[MEASURE] - TARGET[MEASURE]
-- CURRENT SALES - AVERAGE SALES, CURRENT YEAR SALES - PREVIOUS YEAR SALES (YOY ANALYSIS)
-- CURRENT SALES - LOWEST SALES


-- ANALYZE THE YEARLY PERFORMANCE OF PRODUCTS BY COMPARING EACH PRODUCT'S SALES TO BOTH
-- ITS AVERAGE SALES PERFORMANCE AND THE PREVIOUS YEAR'S SALES.

	WITH YEARLY_PRODUCT_SALES AS (
	SELECT 
		YEAR(order_date) AS ORDER_DATE,
		P.product_name,
		SUM(S.sales_amount) AS CURRENT_SALES
	FROM GOLD.fact_sales S
	LEFT JOIN GOLD.dim_products P
	ON S.product_key = P.product_key
	WHERE S.order_date IS NOT NULL
	GROUP BY YEAR(order_date),P.product_name
	)

	SELECT 
		ORDER_DATE,
		product_name,
		CURRENT_SALES,
		AVG(CURRENT_SALES) OVER(PARTITION BY product_name) AS AVG_SALES,
		CURRENT_SALES - AVG(CURRENT_SALES) OVER(PARTITION BY product_name) AS DIFF_AVG,
		CASE
			WHEN CURRENT_SALES - AVG(CURRENT_SALES) OVER(PARTITION BY product_name) > 0 
				THEN 'ABOVE AVG'
			WHEN CURRENT_SALES - AVG(CURRENT_SALES) OVER(PARTITION BY product_name) < 0 
				THEN 'BELOW AVG'
			ELSE 'AVG'
		END AVG_CHANGE,
		--YOY ANALYSIS
		LAG(CURRENT_SALES) OVER(PARTITION BY product_name ORDER BY ORDER_DATE) AS PY_SALE,
		CURRENT_SALES - LAG(CURRENT_SALES) OVER(PARTITION BY product_name ORDER BY ORDER_DATE) AS DIFF_PY,
		CASE
			WHEN CURRENT_SALES - LAG(CURRENT_SALES) OVER(PARTITION BY product_name ORDER BY ORDER_DATE) > 0 
				THEN 'INCREASE'
			WHEN CURRENT_SALES - LAG(CURRENT_SALES) OVER(PARTITION BY product_name ORDER BY ORDER_DATE) < 0 
				THEN 'DECREASE'
			ELSE 'NO CHANGE'
		END PY_CHANGE
	FROM YEARLY_PRODUCT_SALES 
	ORDER BY product_name, ORDER_DATE


--STEP 10: PART TO WHOLE PROPORTIONAL
--         ANALYZE HOW AN INDUVISUAL PART IS PERFORMING COMPARED TO THE OVERALL ,
--         ALLOWING US TO UNDERSTAND WHICH CATEGORY HAS THE MOST IMPECT ON THE BUSINESS

--  ( MEASURE / TOTAL MEASURE ) * 100  BY  DIMENSION
--  SALES / TOTAL SALES BY CATEGORY , QUANTITY / TOTAL QUANTITY 

-- WHICH CATEGORY CONTRIBUTE THE MOST TO OVERALL SALES

WITH TOTAL_CATEGORY_SALES AS (
SELECT
	P.category AS CATEGORY,
	SUM(F.sales_amount) AS TOTAL_SALES
FROM GOLD.fact_sales F
LEFT JOIN GOLD.dim_products P
ON F.product_key = P.product_key
GROUP BY P.category)

SELECT 
	CATEGORY,
	TOTAL_SALES,
	SUM(TOTAL_SALES) OVER () AS OVERALL_SALES,
	CONCAT(ROUND((CAST(TOTAL_SALES AS float)*100/SUM(TOTAL_SALES) OVER ()), 2), '%') AS IMPACT_PERCENTAGE
FROM TOTAL_CATEGORY_SALES
ORDER BY TOTAL_SALES DESC



-- STEP 11: DATA SEGMENTATION
--GROUP THE DATA BASED ON A SPECIFIC RANGE
--HELPS UNDERSTAND THE CORRELATION BETWEEN TWO MEASURES

-- [MEASURE] BY [MEASURE]
-- TOTAL PRODUCTS BY SALE RANGE, TOTAL CUSTOMER BY AGE

-- SEGMENT PRODUCTS INTO COST RANGES AND COUNT HOW MANY PRODUCTS FALL INTO EACH SEGMENT 

WITH PRODUCT_SEGMENT AS (
SELECT 
	product_key,
	product_name,
	cost,
	CASE 
		WHEN COST < 100 THEN 'BELOW 100'
		WHEN COST BETWEEN 100 AND 500 THEN '100-500'
		WHEN COST BETWEEN 500 AND 1000 THEN '500-1000'
		ELSE 'ABOVE 1000'
	END cost_range
FROM GOLD.dim_products
)

SELECT
	cost_range,
	COUNT(product_key) AS CNT_SEGMENT
FROM PRODUCT_SEGMENT
GROUP BY COST_RANGE
ORDER BY CNT_SEGMENT DESC 


/*
Group customers into three segments based on their spending behavior:
	- VIP: Customers with at least 12 months of history and spending more than €5,000.
	- Regular: Customers with at least 12 months of history but spending €5,000 or less.
	- New: Customers with a lifespan less than 12 months.
And find the total number of customers by each group
*/

WITH CUSTOMER_SPENDING AS (
SELECT	
	C.customer_key,
	SUM(F.sales_amount) AS TOTAL_SPENDING,
	MIN(F.order_date) AS FIRST_ORDER,
	MAX(F.order_date) AS LAST_ORDER,
	DATEDIFF(MONTH,MIN(F.order_date), MAX(F.order_date)) AS LIFE_SPAN
FROM GOLD.FACT_SALES F
LEFT JOIN GOLD.dim_customers C
ON F.customer_key = C.customer_key
GROUP BY C.customer_key
)

SELECT 
	COUNT(customer_key) AS TOTAL_CUSTOMER,
	CUSTOMER_TYPE
FROM (
	SELECT
		customer_key,
		CASE
			WHEN LIFE_SPAN >= 12 AND TOTAL_SPENDING > 5000 THEN 'VIP'
			WHEN LIFE_SPAN >= 12 AND TOTAL_SPENDING <= 5000 THEN 'REGULAR'
			WHEN LIFE_SPAN <= 12 THEN 'NEW'
		END 'CUSTOMER_TYPE'
	FROM CUSTOMER_SPENDING
	)T
GROUP BY CUSTOMER_TYPE
ORDER BY TOTAL_CUSTOMER


--STEP 12: COMPLEX REPORT 

/*
===============================================================================
Customer Report
===============================================================================
Purpose:
    - This report consolidates key customer metrics and behaviors

Highlights:
    1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
    3. Aggregates customer-level metrics:
	   - total orders
	   - total sales
	   - total quantity purchased
	   - total products
	   - lifespan (in months)
    4. Calculates valuable KPIs:
	    - recency (months since last order)
		- average order value
		- average monthly spend
===============================================================================
*/

/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
---------------------------------------------------------------------------*/
--CREATE VIEW gold.report_customers AS

WITH base_query AS (
	SELECT 
		F.order_number,
		F.product_key,
		F.order_date,
		F.sales_amount,
		F.quantity,
		C.customer_key,
		C.customer_number,
		CONCAT(C.first_name,' ',C.last_name) AS CUSTOMER_NAME,
		DATEDIFF(YEAR,C.birthdate,GETDATE()) AS AGE
	FROM GOLD.fact_sales F
	LEFT JOIN GOLD.dim_customers C
	ON F.customer_key = C.customer_key
	WHERE order_date IS NOT NULL
)

/*---------------------------------------------------------------------------
2) Customer Aggregations: Summarizes key metrics at the customer level
---------------------------------------------------------------------------*/
, customer_aggregation AS (
	SELECT 
			customer_key,
			customer_number,
			CUSTOMER_NAME,
			AGE,
			COUNT(order_number) AS TOTAL_ORDERS,
			SUM(sales_amount) AS TOTAL_SALES,
			SUM(quantity) AS TOTAL_QUANTITY,
			COUNT(DISTINCT product_key) AS TOTAL_PRODUCT,
			MAX(order_date) AS LAST_ORDER_DATE,
			DATEDIFF(MONTH,MIN(order_date), MAX(order_date)) AS LIFE_SPAN
	FROM base_query
	GROUP BY 
		customer_key,
		customer_number,
		CUSTOMER_NAME,
		AGE
	)

SELECT 
	customer_key,
	customer_number,
	CUSTOMER_NAME,
	AGE,
	CASE
		WHEN AGE < 20 THEN 'UNDER 20'
		WHEN AGE BETWEEN 20 AND 29 THEN '20-29'
		WHEN AGE BETWEEN 30 AND 39 THEN '30-39'
		WHEN AGE BETWEEN 40 AND 49 THEN '40-49'
		ELSE '50 AND ABOVE'
	END 'AGE_GROUP',
	CASE
		WHEN LIFE_SPAN >= 12 AND TOTAL_SALES > 5000 THEN 'VIP'
		WHEN LIFE_SPAN >= 12 AND TOTAL_SALES <= 5000 THEN 'REGULAR'
		ELSE 'NEW'
	END 'CUSTOMER_TYPE',
	DATEDIFF(MONTH,LAST_ORDER_DATE,GETDATE()) AS months_last_order,
	LIFE_SPAN,
	CASE 
		WHEN TOTAL_ORDERS = 0 THEN 0
		ELSE TOTAL_SALES/TOTAL_ORDERS
	END AVG_ORDER_VALUE,

	CASE
		WHEN LIFE_SPAN = 0 THEN TOTAL_SALES
		ELSE TOTAL_SALES/LIFE_SPAN 
	END AVG_MONTH_SPEND,

	TOTAL_ORDERS,
	TOTAL_SALES,
	TOTAL_QUANTITY,
	TOTAL_PRODUCT
FROM customer_aggregation