USE retail_events_db

SELECT * FROM fact_events

SELECT * FROM dim_campaigns

SELECT * FROM dim_products

SELECT * FROM dim_stores

-- 1. High-value products
SELECT *
FROM fact_events
WHERE base_price > 500 AND promo_type = 'BOGOF'

-- 2. Overview of stores in easch city 
SELECT st.city, COUNT(fe.store_id) as store_count
FROM fact_events fe
JOIN dim_stores st
ON st.store_id = fe.store_id
GROUP BY st.city
ORDER BY store_count DESC

-- 3. Revenues before and after each campaign
SELECT dc.campaign_name, SUM(revenue_before_promo) AS total_revenue_before_promo, SUM(revenue_after_promo) AS total_revenue_after_promo
FROM (
SELECT store_id, campaign_id, product_code, promo_type, SUM(base_price * quantity_sold_before_promo) AS revenue_before_promo,
CASE 
	WHEN promo_type = '50% OFF' THEN SUM(base_price*0.5 * quantity_sold_after_promo)
	WHEN promo_type = '25% OFF' THEN SUM(base_price*0.75 * quantity_sold_after_promo)
	WHEN promo_type = '33% OFF' THEN SUM(base_price*0.67 * quantity_sold_after_promo)
	WHEN promo_type = 'BOGOF' THEN SUM(base_price* quantity_sold_after_promo)
	WHEN promo_type = '500 Cashback' THEN SUM((base_price-500) * quantity_sold_after_promo)
	ELSE null
END AS revenue_after_promo
FROM fact_events
GROUP BY store_id, campaign_id, product_code, promo_type
) AS sub1
JOIN dim_campaigns dc
ON dc.campaign_id = sub1.campaign_id
GROUP BY dc.campaign_name

-- 4. Incremental Sold Quantity (ISU%) during Diwali
WITH SoldQuantity AS (
	SELECT 
		*,
		CASE WHEN promo_type = 'BOGOF' THEN quantity_sold_after_promo*2
		ELSE quantity_sold_after_promo END AS actual_quantity
	FROM fact_events
)
SELECT 
	category, 
	incremental_sold_quantity_percentage,
	RANK() OVER(ORDER BY incremental_sold_quantity_percentage DESC) AS rank_order
FROM (
	SELECT 
		dp.category,
		SUM(quantity_sold_before_promo) AS total_sold_before_promo,
		SUM(actual_quantity - quantity_sold_before_promo) AS incremental_sold_quantity,
		ROUND((CAST(SUM(actual_quantity - quantity_sold_before_promo) AS float) / NULLIF(SUM(quantity_sold_before_promo), 0)) * 100,2) AS incremental_sold_quantity_percentage
	FROM SoldQuantity sq
	JOIN dim_products dp ON dp.product_code = sq.product_code
	JOIN dim_campaigns dc ON dc.campaign_id = sq.campaign_id
	WHERE campaign_name = 'Diwali'
	GROUP BY dp.category
) AS sub1
GROUP BY category, incremental_sold_quantity_percentage

-- 5. Top 5 products based on Incremental Revenue (IR%) across all campaigns
WITH PromotionIR AS (
	SELECT
		*,
		CASE 
			WHEN promo_type = '50% OFF' THEN (base_price*0.5)
			WHEN promo_type = '25% OFF' THEN (base_price*0.75)
			WHEN promo_type = '33% OFF' THEN (base_price*0.67)
			WHEN promo_type = 'BOGOF' THEN base_price
			WHEN promo_type = '500 Cashback' THEN (base_price-500)
			ELSE null
		END AS discount_price
	FROM fact_events
),
Revenue AS (
	SELECT 
		*,
		CAST(quantity_sold_before_promo * base_price AS float) AS revenue_before_promo,
		CAST(quantity_sold_after_promo * discount_price AS float) AS revenue_after_promo
	FROM PromotionIR
)

SELECT
	TOP 5 product_name,
	category,
	incremental_revenue_percentage
FROM (
	SELECT 
		*, 
		ROUND((revenue_after_promo - revenue_before_promo)/revenue_before_promo,4)*100 AS incremental_revenue_percentage
	FROM Revenue
) AS sub1
JOIN dim_products dp
ON dp.product_code = sub1.product_code
ORDER BY incremental_revenue_percentage DESC
