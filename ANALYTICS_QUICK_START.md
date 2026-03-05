# Analytics Dashboard - Quick Start Guide

## 🚀 Installation & Setup

### Step 1: Database Migration (Performance Optimization)

Run the analytics indexes migration to optimize query performance:

```bash
# The migration file is already created at:
# db/migrate/20260305000000_add_analytics_indexes.rb

# Run the migration
rails db:migrate

# Verify indexes were created
rails db
SHOW INDEXES FROM users;
SHOW INDEXES FROM user_match_requests;
SHOW INDEXES FROM purchases;
exit;
```

**Expected Output:**
```
✅ Analytics indexes created successfully
```

### Step 2: Verify File Structure

Ensure all files are in place:

```bash
# Service layer
ls app/services/analytics_service.rb

# Controller
ls app/controllers/analytics_controller.rb

# Views
ls app/views/analytics/index.html.erb
ls app/views/analytics/_analytics_script.html.erb

# Styles
ls app/assets/stylesheets/analytics.css

# Documentation
ls ANALYTICS_DASHBOARD_README.md
```

### Step 3: Asset Compilation

If using production or precompiling assets:

```bash
# Precompile assets (if needed)
rails assets:precompile

# Or restart Rails server in development
rails s
```

### Step 4: Verify Routes

Check that analytics routes are registered:

```bash
rails routes | grep analytics
```

**Expected Output:**
```
analytics GET  /analytics(.:format)      analytics#index
analytics_data GET  /analytics/data(.:format) analytics#data
```

## 📊 Accessing the Dashboard

### Option 1: From Admin Panel

1. Navigate to your app (e.g., `http://localhost:3000`)
2. Log in as an admin user
3. Go to Admin Panel (usually `/test` or the root if you're admin)
4. Click on **"Analytics Dashboard"** card

### Option 2: Direct URL

Simply navigate to: `http://localhost:3000/analytics`

⚠️ **Note**: You must be logged in as an admin user. If not, you'll be redirected to the login page.

## 🔍 First-Time Use

### 1. Initial Load

When you first access the dashboard:
- It will show data for the **last 30 days**
- **Bots are excluded** by default
- Only **active accounts** are shown
- All charts load automatically via AJAX

### 2. Understanding Sections

The dashboard is divided into **7 main sections**:

| Section | What It Shows | Key Metrics |
|---------|---------------|-------------|
| **Growth** | User acquisition trends | New users, cumulative growth, deletions |
| **Engagement** | User activity patterns | DAU, MAU, stickiness ratio |
| **Demographics** | User characteristics | Gender, age, location |
| **Matching** | Dating app core metrics | Matches, likes, conversion rates |
| **Monetization** | Revenue analytics | ARPU, ARPPU, subscriptions |
| **Retention** | User loyalty | Cohorts, churn rate |
| **Insights** | Top performers | Top users, cities |

### 3. Using Filters

#### Quick Filter Examples:

**View iOS users only:**
1. Device Platform → iOS
2. Click "Apply Filters"

**Last 7 days, verified users:**
1. Date Range → Last 7 days
2. Verification → Verified only
3. Click "Apply Filters"

**Compare Spain vs other countries:**
1. Country → Spain
2. Note the metrics
3. Change Country → All
4. Compare the differences

#### Custom Date Range:
1. Date Range → Custom range
2. Select Start Date and End Date
3. Click "Apply Filters"

## 📈 Understanding Key Metrics

### DAU / MAU Ratio (Stickiness)
- **What**: Daily Active Users / Monthly Active Users
- **Formula**: (DAU / MAU) × 100
- **Good value**: > 20%
- **Excellent value**: > 30%

### Match Conversion Rate
- **What**: Percentage of likes that result in matches
- **Formula**: (Total Matches / Total Likes) × 100
- **Good value**: 5-10%
- **Excellent value**: > 10%

### ARPU (Average Revenue Per User)
- **What**: Total revenue divided by all users
- **Formula**: Total Revenue / Total Users
- **Use**: Measure overall monetization

### ARPPU (Average Revenue Per Paying User)
- **What**: Total revenue divided by paying users only
- **Formula**: Total Revenue / Paying Users
- **Use**: Measure subscriber value

### Churn Rate
- **What**: Percentage of users who become inactive
- **Formula**: (Churned Users / Total Users) × 100
- **Good value**: < 10%
- **Action needed**: > 20%

## 🛠️ Troubleshooting

### Charts not appearing?

**Check 1: JavaScript Console**
```javascript
// Open browser console (F12)
// Look for errors
```

**Check 2: Chart. loading**
```html
<!-- Verify Chart.js is loaded -->
<script src="Chart.js CDN"></script>
```

**Check 3: Network Tab**
- Open Network tab in browser
- Click "Apply Filters"
- Look for `/analytics/data?section=...` requests
- Check if they return 200 OK

### Slow performance?

**Option 1: Check indexes**
```sql
-- Verify indexes exist
SHOW INDEXES FROM users WHERE Key_name LIKE 'idx_%';
```

**Option 2: Reduce date range**
- Use shorter periods (7 days instead of all time)
- Indices work better with smaller datasets

**Option 3: Add caching** (Advanced)
```ruby
# In analytics_controller.rb
def growth_data
  Rails.cache.fetch("analytics/growth/#{@filters.hash}", expires_in: 1.hour) do
    # ... existing code
  end
end
```

### No data showing?

**Check 1: Do you have data?**
```bash
rails console
User.count
UserMatchRequest.count
Purchase.count
```

**Check 2: Filters too restrictive?**
- Try "All time" date range
- Set all filters to "All"
- Include bots

**Check 3: Admin permissions?**
```ruby
# Rails console
current_user = User.find(YOUR_USER_ID)
current_user.admin?  # Should return true
```

## 🎯 Common Use Cases

### Weekly Review
1. Date Range: Last 7 days
2. Review:
   - New users growth
   - Match conversion rate
   - Revenue trends
3. Compare to previous period manually

### Monthly Business Review
1. Date Range: Last 30 days
2. Focus on:
   - DAU/MAU ratio
   - ARPU / ARPPU
   - Churn rate
   - Top performing cities

### Platform Health Check
1. Set filters to exclude bots
2. Check:
   - Active users percentage
   - Match system conversion
   - User retention cohorts

### iOS vs Android Comparison
1. Set Device Platform: iOS
2. Note key metrics
3. Change to Android
4. Compare differences

### Identify Growth Opportunities
1. Check "Top Cities" insights
2. Look for cities with:
   - High user count
   - Low match rates
3. Focus marketing/matching algorithm there

## 📱 Mobile Access

The dashboard is optimized for desktop but works on tablets:
- iPad: ✅ Full functionality
- Mobile phones: ⚠️ Limited (charts may be small)

**Tip**: For mobile, focus on the key metric cards at the top.

## 🔐 Security Notes

- ✅ Only admin users can access
- ✅ No sensitive user data exposed (only aggregated metrics)
- ✅ All queries are read-only
- ⚠️ Consider IP whitelisting for production

## 📞 Support

### Getting Help

1. **Documentation**: Read `ANALYTICS_DASHBOARD_README.md`
2. **Code**: Check service/controller comments
3. **Logs**: Review `log/development.log` or `log/production.log`
4. **Database**: Verify data exists and indexes are active

### Common Questions

**Q: Can I export the data?**  
A: Not built-in yet. Consider adding CSV export (see documentation for implementation guide).

**Q: Can I schedule automated reports?**  
A: Not built-in. Consider adding with a gems like `whenever` or background jobs.

**Q: How often does data refresh?**  
A: Real-time on filter apply. No auto-refresh (you can add it via JavaScript).

**Q: Can I compare two date ranges?**  
A: Not built-in yet. This is a recommended future enhancement.

---

## ✅ Verification Checklist

Before considering setup complete, verify:

- [ ] Migration ran successfully
- [ ] Can access `/analytics` as admin
- [ ] All 7 sections load without errors
- [ ] Charts render properly
- [ ] Filters work and update charts
- [ ] Key metrics show realistic numbers
- [ ] No console errors in browser
- [ ] Page loads in < 5 seconds (with real data)

---

**🎉 Congratulations!** Your Analytics Dashboard is ready to use.

Explore the data, make informed decisions, and drive platform growth! 📊

---

**Version**: 1.0  
**Last Updated**: March 5, 2026
