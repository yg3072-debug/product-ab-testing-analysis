# Checkout Flow A/B Test — Experiment Readout

**Decision: Need more data before full launch**  
**Experiment:** Existing multi-step checkout vs. simplified single-page checkout  
**Assignment window:** July 1–14, 2026

## Objective and Hypothesis

The experiment evaluated whether simplifying checkout increases completed purchases without materially worsening payment reliability, technical stability, order quality, or customer value.

- **Null hypothesis:** treatment and control have equal 24-hour purchase conversion.
- **Alternative hypothesis:** treatment and control purchase conversion differ.

## Design and Population

Users were randomized to one persistent experiment group. The primary exposed-user analysis included eligible users with a first valid checkout exposure after assignment and a complete 24-hour outcome window. Duplicate assignments and events, cross-assigned users, internal/test/bot traffic, and immature exposures were excluded.

- **Analysis unit:** one row per user
- **Mature population:** 15,467 users
- **Control:** 7,754 users
- **Treatment:** 7,713 users
- **Primary metric:** users completing an attributed purchase / mature checkout-exposed users

## Primary Result

| Metric | Control | Treatment | Treatment − Control |
|---|---:|---:|---:|
| Purchase conversion | 27.47% | 29.63% | **+2.16 pp** |
| Relative lift | — | — | **+7.85%** |

A pre-specified two-sided two-proportion z-test produced **z = 2.968** and **p = 0.0030**. The 95% confidence interval for absolute lift was **+0.73 to +3.58 percentage points**. The treatment therefore produced a statistically significant positive conversion effect. The point estimate exceeded the +1.0-point business threshold, although the interval still included effects below that threshold.

## Secondary and Guardrail Results

| Metric | Control | Treatment | Difference | Interpretation |
|---|---:|---:|---:|---|
| Median completion time | 28.13 min | 26.82 min | -1.31 min | Faster among purchasers |
| Payment failure | 5.36% | 5.13% | -0.23 pp | No observed worsening |
| Retained revenue / exposed user | $24.52 | $26.33 | **+$1.81** | +7.40%; 95% CI +$0.30 to +$3.33 |
| Checkout error | 3.07% | 3.49% | +0.42 pp | 95% CI -0.14 to +0.98 pp |
| Refund/cancellation | 5.68% | 6.48% | +0.80 pp | 95% CI -0.61 to +2.21 pp |

Payment failure did not increase, while retained revenue improved. Checkout error and refund/cancellation differences were not statistically significant, but their intervals still allowed practically relevant harm. Because no non-inferiority margins were pre-specified, non-significance cannot be interpreted as proof that these guardrails are safe.

## Segment Findings

All ten pre-specified subgroup point estimates were positive. Email and social traffic showed the largest lifts, but direct heterogeneity tests found no confirmed effect differences after Holm correction: user type `p_adj = 1.0000`, device `p_adj = 1.0000`, and traffic source `p_adj = 0.1883`. The evidence does not support a segment-targeted rollout.

## Recommendation and Limitations

Do not proceed immediately to a full launch. Treat the simplified checkout as a strong candidate and run a confirmatory extension that pre-specifies acceptable non-inferiority margins for checkout errors and refund/cancellation, while continuing to monitor retained revenue and payment reliability. A targeted rollout is not justified by the current segment evidence.

The analysis uses simulated data and an exposed-user estimand rather than all assigned users. Segment analyses are exploratory, completion time is conditioned on purchase, and live experimentation would additionally require checks for interference, logging changes, and sequential peeking.
