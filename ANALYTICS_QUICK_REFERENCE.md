# 📊 Analytics Dashboard - Quick Reference Card

## 🔗 Access
**URL**: `/analytics`  
**Required**: Admin user authentication

---

## 🎯 Key Metrics at a Glance

| Metric | What It Measures | Good Value | Action If Low |
|--------|------------------|------------|---------------|
| **DAU/MAU Ratio** | Platform stickiness | > 20% | Improve engagement features |
| **Match Conversion** | Like → Match rate | > 5% | Optimize algorithm |
| **Churn Rate** | Users becoming inactive | < 10% | Improve retention |
| **ARPU** | Revenue per user | Increasing | Enhance monetization |
| **ARPPU** | Revenue per paying user | > €10 | Add premium features |

---

## 🔍 Filter Quick Combos

### Most Popular Filters

**New Users This Week**
```
Date Range: Last 7 days
Bot Filter: Exclude bots
Account Status: Active users
```

**Premium User Analysis**
```
Subscription Type: Premium
Verification: Verified only
Bot Filter: Exclude bots
```

**iOS User Metrics**
```
Device Platform: iOS
Account Status: Active users
Bot Filter: Exclude bots
```

**Spain Market Analysis**
```
Country: Spain
Account Status: Active users
Date Range: Last 30 days
```

---

## 📈 Chart Types Guide

| Chart | Best For | Example Use |
|-------|----------|-------------|
| **Line** | Trends over time | Daily active users |
| **Bar** | Comparisons | Top cities |
| **Pie/Doughnut** | Distributions | Gender split |
| **Histogram** | Ranges | Age groups |
| **Table** | Cohorts | Retention analysis |

---

## 🚀 Common Questions Answered

**Q: Are users growing?**  
→ Check: Growth → New Users Over Time

**Q: Is engagement healthy?**  
→ Check: Engagement → DAU/MAU Ratio

**Q: Is the matching system working?**  
→ Check: Matching → Match Conversion Rate

**Q: Is monetization improving?**  
→ Check: Monetization → Revenue Over Time + ARPU

**Q: Are we retaining users?**  
→ Check: Retention → Churn Rate + Cohorts

**Q: Which cities perform best?**  
→ Check: Insights → Top Cities by Engagement

---

## ⚡ Power User Tips

### Tip 1: Quick Comparisons
1. Apply filter (e.g., Gender: Female)
2. Screenshot or note metrics
3. Change filter (e.g., Gender: Male)
4. Compare values

### Tip 2: Find Problem Areas
1. Set Date Range: Last 30 days
2. Check Churn Rate
3. If high (>20%), check:
   - Match Conversion (too low?)
   - Engagement metrics (declining?)
   - Retention cohorts (drop-off point?)

### Tip 3: Identify Growth Opportunities
1. Check Demographics → Top Cities
2. Sort by user count
3. Cross-reference with Matches per User
4. Cities with users but low matches = opportunity

### Tip 4: Monitor Platform Health
Weekly checklist:
- [ ] DAU/MAU ratio stable or growing
- [ ] Match conversion > 5%
- [ ] Churn rate < 10%
- [ ] ARPU trending up
- [ ] New users growing

---

## 🎨 Dashboard Sections

### 1️⃣ Growth
**Focus**: User acquisition  
**Key Questions**: How fast are we growing? Are bots a problem?

### 2️⃣ Engagement
**Focus**: User activity  
**Key Questions**: How often do users return? Are they active?

### 3️⃣ Demographics
**Focus**: User characteristics  
**Key Questions**: Who are our users? Where are they from?

### 4️⃣ Matching
**Focus**: Core dating features  
**Key Questions**: Are matches happening? What's the conversion?

### 5️⃣ Monetization
**Focus**: Revenue  
**Key Questions**: Are we making money? Who's paying?

### 6️⃣ Retention
**Focus**: User loyalty  
**Key Questions**: Do users stay? When do they churn?

### 7️⃣ Insights
**Focus**: Top performers  
**Key Questions**: Who are power users? Which cities are best?

---

## 🔢 Formulas

```
DAU/MAU Ratio = (Daily Active Users / Monthly Active Users) × 100

Match Conversion = (Total Matches / Total Likes) × 100

Churn Rate = (Churned Users / Total Users) × 100

ARPU = Total Revenue / Total Users

ARPPU = Total Revenue / Paying Users

Premium Conversion = (Paying Users / Total Users) × 100
```

---

## 🚨 Warning Signs

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| DAU/MAU | < 15% | < 10% | Engagement campaign |
| Match Conv. | < 3% | < 1% | Fix algorithm |
| Churn | 15-20% | > 20% | Retention analysis |
| ARPU | Declining | Dropping >20% | Review pricing |
| New Users | Flat | Declining | Marketing boost |

---

## 📱 Keyboard Shortcuts

None currently, but you can:
- **Refresh Data**: Click "Apply Filters"
- **Reset Filters**: Reload page
- **Print Report**: Ctrl/Cmd + P (optimized for printing)

---

## 🎯 Weekly Review Checklist

**Every Monday Morning:**

1. **Check Last Week's Performance**
   - Date Range: Last 7 days
   - Bot Filter: Exclude bots
   
2. **Key Metrics Review**
   - [ ] New users vs previous week
   - [ ] DAU/MAU ratio
   - [ ] Match conversion rate
   - [ ] Revenue generated
   - [ ] Churn rate

3. **Identify Issues**
   - [ ] Any metric dropped >20%?
   - [ ] Any section showing warning signs?
   - [ ] Any anomalies in charts?

4. **Plan Actions**
   - [ ] Document findings
   - [ ] Create action items
   - [ ] Share with team

---

## 🔄 Data Refresh Rates

- **Real-time**: No (manual refresh via "Apply Filters")
- **Cache**: None (all queries fresh)
- **Historical**: All data since app launch

**To Update:**
1. Change filters
2. Click "Apply Filters"
3. Wait 2-5 seconds for charts to reload

---

## 🎓 Learn More

- **Full Documentation**: `ANALYTICS_DASHBOARD_README.md`
- **Setup Guide**: `ANALYTICS_QUICK_START.md`
- **Technical Details**: `app/services/analytics_service.rb`

---

## 💡 Pro Tips

1. **Use Custom Ranges** for precise periods
2. **Combine Multiple Filters** for deep insights
3. **Track Trends Over Time** not just absolute numbers
4. **Compare Segments** (iOS vs Android, Premium vs Free)
5. **Focus on Ratios** more than counts (DAU/MAU, Conversion)
6. **Check Retention Cohorts** to spot when users drop off
7. **Monitor Top Cities** for geographic expansion opportunities

---

## ⚠️ Common Mistakes

❌ Comparing different time periods without noting filter changes  
❌ Including bots in engagement analysis  
❌ Ignoring deleted accounts in growth metrics  
❌ Focusing only on absolute numbers, not trends  
❌ Not segmenting by platform/gender when needed  
❌ Setting date range too long (slows queries)  

---

## 📞 Need Help?

1. Check this quick reference
2. Read `ANALYTICS_QUICK_START.md`
3. Review troubleshooting section
4. Check Rails logs
5. Contact development team

---

## 🏆 Dashboard Goals

The analytics dashboard helps you:

✅ Understand user behavior  
✅ Identify growth opportunities  
✅ Monitor platform health  
✅ Make data-driven decisions  
✅ Optimize monetization  
✅ Improve retention  
✅ Track key metrics  

---

**Print this for your desk! 🖨️**

*Version 1.0 | March 2026*
