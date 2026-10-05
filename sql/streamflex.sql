--_____________________task 01_____________________--
WITH show_totals AS (
    SELECT u.country_code, s.show_id, s.title,
           SUM(v.minutes_watched) AS total_minutes
    FROM sf.users u
		join sf.viewings v on u.user_id = v.user_id
		join sf.shows s on v.show_id = s.show_id
    GROUP BY u.country_code, s.show_id, s.title
),
country_avg AS (
    SELECT country_code, AVG(total_minutes) AS avg_minutes
    FROM show_totals
    GROUP BY country_code
)
SELECT
    st.country_code,
    st.show_id,
    st.title,
    FLOOR(st.total_minutes / 60.0) AS total_hours,
    DENSE_RANK() OVER (PARTITION BY st.country_code ORDER BY st.total_minutes DESC) AS hit_rank_in_country
FROM show_totals st
	JOIN country_avg ca ON ca.country_code = st.country_code
WHERE st.total_minutes >= 60000
  	AND st.total_minutes > ca.avg_minutes
ORDER BY st.country_code, hit_rank_in_country;


--_____________________task 02_____________________--
with checking as (
SELECT
    u.user_id,
    EXISTS (
        SELECT 1
        FROM sf.subscriptions s
        JOIN sf.plans p ON p.plan_id = s.plan_id
        WHERE s.user_id = u.user_id
          AND p.monthly_price > 0
    ) AS is_paid 
FROM sf.users u
),
paid_shows AS (
    SELECT DISTINCT v.show_id
    FROM sf.viewings v
    JOIN checking c ON c.user_id = v.user_id
    WHERE c.is_paid
),
free_shows AS (
    SELECT DISTINCT v.show_id
    FROM sf.viewings v
    JOIN checking c ON c.user_id = v.user_id
    WHERE NOT c.is_paid
),
result AS (
    SELECT show_id FROM paid_shows
    EXCEPT
    SELECT show_id FROM free_shows
)
SELECT s.show_id, s.title
FROM sf.shows s
JOIN result r ON r.show_id = s.show_id;

--_____________________task 03_____________________--
WITH max_price AS (
    SELECT MAX(monthly_price) AS m FROM sf.plans
),
country_avg AS (
    SELECT u.country_code, AVG(p.amount) AS avg_payment
    FROM sf.payments p
    JOIN sf.subscriptions s ON s.subscription_id = p.subscription_id
    JOIN sf.users u ON u.user_id = s.user_id
    WHERE p.is_refund = false AND p.amount > 0
    GROUP BY u.country_code
)
SELECT ca.country_code, ca.avg_payment
FROM country_avg ca
CROSS JOIN max_price mp
WHERE ca.avg_payment > mp.m;

--_____________________task 04_____________________--
WITH gross AS (
    SELECT amount FROM sf.payments
    WHERE is_refund = false AND amount > 0
),
refunds AS (
    SELECT amount FROM sf.payments
    WHERE NOT (is_refund = false AND amount > 0) 
),
net_union AS (
    SELECT SUM(amount) AS net_union
    FROM (
        SELECT amount FROM gross
        UNION
        SELECT amount FROM refunds
    ) AS u
),
net_union_all AS (
    SELECT SUM(amount) AS net_union_all
    FROM (
        SELECT amount FROM gross
        UNION ALL
        SELECT amount FROM refunds
    ) AS u
)
SELECT
    (SELECT SUM(amount) FROM gross) AS gross_revenue,
    (SELECT net_union_all FROM net_union_all) AS net_revenue,
    (SELECT net_union FROM net_union) AS net_union;
	
--_____________________task 05_____________________--
WITH device_stats AS (
    SELECT
        u.user_id,
        v.device_type,
        SUM(v.minutes_watched) AS total_minutes,
        COUNT(DISTINCT v.show_id) AS distinct_shows
    FROM sf.viewings v
    JOIN sf.users u ON u.user_id = v.user_id
    GROUP BY u.user_id, v.device_type
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY user_id ORDER BY total_minutes DESC) AS device_rank_for_user
    FROM device_stats
)
SELECT
    user_id,
    device_type,
    total_minutes,
    distinct_shows,
    device_rank_for_user
FROM ranked
WHERE device_rank_for_user <= 2
ORDER BY user_id, device_rank_for_user;

--_____________________task 06_____________________--
WITH dates AS (
    SELECT d::date AS revenue_date
    FROM generate_series(
        (SELECT MIN(paid_at)::date FROM sf.payments),
        (SELECT MAX(paid_at)::date FROM sf.payments),
        interval '1 day'
    ) AS d
),
countries AS (
    SELECT DISTINCT country_code FROM sf.users
),
calendar AS (
    SELECT d.revenue_date, c.country_code
    FROM dates d
    CROSS JOIN countries c
),
daily_revenue AS (
    SELECT
        p.paid_at::date AS revenue_date,
        u.country_code,
        SUM(p.amount) AS daily_revenue
    FROM sf.payments p
    JOIN sf.subscriptions s ON s.subscription_id = p.subscription_id
    JOIN sf.users u ON u.user_id = s.user_id
    WHERE p.is_refund = false AND p.amount > 0
    GROUP BY p.paid_at::date, u.country_code
),
filled AS (
    SELECT
        cal.revenue_date,
        cal.country_code,
        COALESCE(dr.daily_revenue, 0) AS daily_revenue
    FROM calendar cal
    LEFT JOIN daily_revenue dr
        ON dr.revenue_date = cal.revenue_date
       AND dr.country_code = cal.country_code
)
SELECT
    revenue_date,
    country_code,
    daily_revenue,
    SUM(daily_revenue) OVER (
        PARTITION BY country_code
        ORDER BY revenue_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_revenue
FROM filled
ORDER BY country_code, revenue_date;
	
--_____________________task 07_____________________--
WITH RECURSIVE org AS (
    (
        SELECT 
            u.user_id, 
            u.full_name, 
            0 AS level, 
            u.user_id::text AS path 
        FROM sf.users u 
        WHERE u.user_id = 1
    )
    UNION ALL
    (
        SELECT 
            u.user_id, 
            u.full_name, 
            org.level + 1 AS level, 
            org.path || ' > ' || u.user_id::text AS path 
        FROM sf.users u 
        JOIN org ON u.referrer_user_id = org.user_id 
        WHERE org.level < 10
    )
) 
SELECT * 
FROM org 
ORDER BY level, user_id;

--_____________________task 08_____________________--
WITH viewing_stats AS (
    SELECT
        v.user_id,
        SUM(v.minutes_watched) AS total_minutes
    FROM sf.viewings v
    GROUP BY v.user_id
),
payment_stats AS (
    SELECT
        s.user_id,
        SUM(p.amount) AS paid_revenue
    FROM sf.payments p
    JOIN sf.subscriptions s ON s.subscription_id = p.subscription_id
    WHERE p.amount > 0
      AND p.is_refund = false
    GROUP BY s.user_id
),
subscription_stats AS (
    SELECT
        s.user_id,
        COUNT(*) AS active_subscriptions
    FROM sf.subscriptions s
    WHERE s.cancelled_at IS NULL
    GROUP BY s.user_id
),
user_stats AS (
    SELECT
        u.user_id,
        u.full_name,
        COALESCE(vs.total_minutes, 0)        AS total_minutes,
        COALESCE(ps.paid_revenue, 0)         AS paid_revenue,
        COALESCE(ss.active_subscriptions, 0) AS active_subscriptions
    FROM sf.users u
    LEFT JOIN viewing_stats       vs ON vs.user_id = u.user_id
    LEFT JOIN payment_stats       ps ON ps.user_id = u.user_id
    LEFT JOIN subscription_stats  ss ON ss.user_id = u.user_id
),
minutes_top AS (
    SELECT
        'minutes' AS metric_type,
        user_id,
        full_name,
        total_minutes AS metric_value,
        ROW_NUMBER() OVER (ORDER BY total_minutes DESC) AS rank_in_metric
    FROM user_stats
    ORDER BY total_minutes DESC
    LIMIT 10
),
revenue_top AS (
    SELECT
        'revenue' AS metric_type,
        user_id,
        full_name,
        paid_revenue AS metric_value,
        ROW_NUMBER() OVER (ORDER BY paid_revenue DESC) AS rank_in_metric
    FROM user_stats
    ORDER BY paid_revenue DESC
    LIMIT 10
)
SELECT * FROM minutes_top
UNION ALL
SELECT * FROM revenue_top;

--_____________________task 09_____________________--
create view sf.active_premium_subscriptions as
select
	s.subscription_id,
	s.user_id,
	s.plan_id,
	s.started_at,
	s.cancelled_at,
	p.monthly_price
from 
	sf.subscriptions s
	join sf.plans p on p.plan_id = s.plan_id
where 
	s.cancelled_at IS null and
	p.is_active = true and
	p.is_premium = true
	
CREATE OR REPLACE FUNCTION sf.active_premium_subscriptions_io()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- проверяем, что план активный и премиальный
        IF NOT EXISTS (
            SELECT 1 FROM sf.plans
            WHERE plan_id = NEW.plan_id
              AND is_active = true
              AND is_premium = true
        ) THEN
            RAISE EXCEPTION 'Нельзя вставить подписку на непремиальный или неактивный план';
        END IF;

        INSERT INTO sf.subscriptions (user_id, plan_id, started_at, cancelled_at, auto_renew)
        VALUES (NEW.user_id, NEW.plan_id, NEW.started_at, NULL, true);

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        -- запрещаем "отменять" подписку через представление
        IF NEW.cancelled_at IS NOT NULL THEN
            RAISE EXCEPTION 'Нельзя установить cancelled_at через представление';
        END IF;

        -- если меняется plan_id — проверяем новый план
        IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
            IF NOT EXISTS (
                SELECT 1 FROM sf.plans
                WHERE plan_id = NEW.plan_id
                  AND is_active = true
                  AND is_premium = true
            ) THEN
                RAISE EXCEPTION 'Нельзя перевести подписку на непремиальный или неактивный план';
            END IF;
        END IF;

        UPDATE sf.subscriptions
        SET user_id      = NEW.user_id,
            plan_id      = NEW.plan_id,
            started_at   = NEW.started_at
        WHERE subscription_id = OLD.subscription_id;

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM sf.subscriptions
        WHERE subscription_id = OLD.subscription_id;

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_aps_insert
INSTEAD OF INSERT ON sf.active_premium_subscriptions
FOR EACH ROW EXECUTE FUNCTION sf.active_premium_subscriptions_io();

CREATE TRIGGER trg_aps_update
INSTEAD OF UPDATE ON sf.active_premium_subscriptions
FOR EACH ROW EXECUTE FUNCTION sf.active_premium_subscriptions_io();

CREATE TRIGGER trg_aps_delete
INSTEAD OF DELETE ON sf.active_premium_subscriptions
FOR EACH ROW EXECUTE FUNCTION sf.active_premium_subscriptions_io();

INSERT INTO sf.active_premium_subscriptions (user_id, plan_id, started_at)
VALUES (1, 3, now());
SELECT * FROM sf.active_premium_subscriptions WHERE user_id = 1;

INSERT INTO sf.active_premium_subscriptions (user_id, plan_id, started_at)
VALUES (1, 1, now());

UPDATE sf.active_premium_subscriptions
SET cancelled_at = now()
WHERE subscription_id = 110;

--_____________________task 10_____________________--
WITH months AS (
    SELECT generate_series(
        date_trunc('month', (SELECT MIN(started_at) FROM sf.subscriptions)),
        date_trunc('month', NOW()),
        interval '1 month'
    )::date AS month_start
),
user_months AS (
    SELECT DISTINCT
        s.user_id,
        m.month_start
    FROM sf.subscriptions s
    JOIN months m
        ON s.started_at < (m.month_start + interval '1 month')
       AND (s.cancelled_at IS NULL OR s.cancelled_at >= m.month_start)
),
user_active AS (
    SELECT
        user_id,
        MIN(month_start) AS start_month,
        COUNT(*)         AS active_months
    FROM user_months
    GROUP BY user_id
)
SELECT
    start_month,
    COUNT(*)            AS cohort_size,
    AVG(active_months)  AS avg_active_months
FROM user_active
GROUP BY start_month
ORDER BY start_month;























