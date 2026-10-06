# Claude's member OAuth endpoint has two monetary response shapes. Normalize
# them once so live/cache validation and the displayed reading cannot disagree.
def amount: type == "number" and . >= 0 and . < 1e15;
def exponent: type == "number" and . == floor and . >= 0 and . <= 6;
def currency: type == "string" and test("^[A-Z]{3}$");
def window: type == "object" and (.utilization | amount);
def money:
    if (.spend | type) == "object" then
        .spend as $s |
        {enabled: $s.enabled, usedMinor: $s.used.amount_minor,
         limitMinor: $s.limit.amount_minor, currency: $s.used.currency,
         exponent: $s.used.exponent, limitCurrency: $s.limit.currency,
         limitExponent: $s.limit.exponent,
         limitKind: (if $s | has("limit") | not then "unknown"
                     elif $s.limit == null then "unlimited" else "finite" end)}
    elif (.extra_usage | type) == "object" then
        .extra_usage as $s |
        {enabled: $s.is_enabled, usedMinor: $s.used_credits,
         limitMinor: $s.monthly_limit, currency: $s.currency,
         exponent: $s.decimal_places, limitCurrency: $s.currency,
         limitExponent: $s.decimal_places,
         limitKind: (if $s | has("monthly_limit") | not then "unknown"
                     elif $s.monthly_limit == null then "unlimited" else "finite" end)}
    else null end;
try (money as $s |
(if $s != null and ($s.enabled | type) == "boolean"
    and ($s.usedMinor | amount) and ($s.currency | currency)
    and ($s.exponent | exponent)
    and ($s.limitKind != "finite" or
         (($s.limitMinor | amount) and $s.limitCurrency == $s.currency
          and $s.limitExponent == $s.exponent))
 then $s | del(.limitCurrency, .limitExponent)
 else null end) as $spend |
{valid: ((.five_hour | window) or (.seven_day | window) or $spend != null),
 spend: $spend}) catch {valid: false, spend: null}
