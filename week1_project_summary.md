# Week 1 Project Summary

## Project Name

E-commerce Product Analytics Mini Project

## One-Sentence Summary

Built a pandas-based product analytics project to measure e-commerce product metrics, diagnose funnel drop-off, analyze user retention, and evaluate a simulated checkout A/B test.

## Business Context

The project simulates a common product analytics workflow for an e-commerce platform. The main goal is to understand user behavior across the product journey, from initial product view to purchase and post-visit retention.

## What I Analyzed

### Product Metrics

I calculated core product KPIs such as DAU, completed GMV, AOV, ARPU, purchase conversion rate, repeat purchase rate, and segment-level performance.

### Funnel Analysis

I analyzed the user journey from product view to purchase and compared non-cumulative versus cumulative funnel definitions. The cumulative funnel was selected for final reporting because it better reflects true user progression.

### Retention Analysis

I calculated exact-day retention based on each user's first active date and built cohort retention matrices to compare user engagement across acquisition cohorts.

### A/B Testing

I simulated a checkout flow A/B test, checked balance across device and first-touch traffic source, calculated conversion uplift, and used a two-proportion z-test to evaluate statistical significance.

## Main Analytical Takeaways

1. Metric definitions matter: the same data can produce different conclusions depending on whether funnel steps are counted independently or cumulatively.
2. Data grain matters: user-level, event-level, and order-level tables must be joined only after defining the correct analysis grain.
3. Retention analysis requires attention to observation windows, especially for users who first appear near the end of the dataset.
4. A/B test results should be interpreted using both business impact and statistical significance.
5. Segment-level patterns are useful for exploration but should not be over-interpreted without sufficient sample size or pre-planned hypotheses.

## Interview Story

I built an e-commerce product analytics mini project using Python and pandas. I started by calculating core product metrics such as DAU, GMV, AOV, ARPU, conversion rate, and repeat purchase rate. Then I moved into funnel analysis to understand where users dropped off from product view to purchase. One key improvement was recognizing that non-cumulative funnel counts can overstate conversion, so I rebuilt the funnel cumulatively to ensure each step was a subset of the previous step.

I also conducted retention and cohort analysis by defining each user's first active date and measuring exact-day retention over time. Finally, I simulated an A/B test for a checkout flow, checked group balance across device and first-touch traffic source, calculated conversion uplift, and used a two-proportion z-test to evaluate statistical significance.

This project implements the full product analytics workflow: defining business questions, choosing the appropriate metric grain, performing the analysis in pandas, resolving metric-definition issues, and translating results into business recommendations.
