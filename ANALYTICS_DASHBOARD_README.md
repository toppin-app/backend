# User Analytics Dashboard Documentation

## Overview

The User Analytics Dashboard is a comprehensive analytics and reporting system for the Toppin dating app admin panel. It provides deep insights into user behavior, platform health, monetization, and engagement metrics.

## Features

### 1. Global Filtering System
The dashboard includes a powerful global filter system that applies to all metrics and charts:

- **Date Range**: Today, Yesterday, Last 7/30/90 days, Last 12 months, All time, Custom range
- **Bot Filter**: Exclude bots, Only bots, Include bots
- **Account Status**: Active users, Deleted accounts, All users
- **Gender**: Female, Male, Non-binary, Couple, All
- **Device Platform**: iOS, Android, All
- **Subscription Type**: Free, Premium, Supreme, All
- **Location**: Country and City filters
- **Verification Status**: Verified, Non-verified, All

### 2. Dashboard Sections

#### Growth Metrics
- New Users Over Time (daily/weekly/monthly)
- Cumulative User Growth
- User Types Distribution (Real users vs Bots vs Deleted)
- Verified vs Non-Verified Users
- Account Deletions Over Time
- Key metrics: Total users, Real users, Bot users, Verified users

#### Engagement Metrics
- Daily Active Users (DAU)
- Weekly Active Users (WAU)
- Monthly Active Users (MAU)
- DAU/MAU Ratio (Platform Stickiness)
- Likes Sent Per Day
- Matches Created Over Time
- Average engagement metrics per user

#### Demographics
- Gender Distribution
- Age Distribution (histogram)
- Top Countries
- Top Cities
- Average Age by Gender

#### Matching System Analytics
- Total Likes Sent
- Total Superlikes Sent
- Total Matches Created
- Match Conversion Rate (Likes → Match)
- Superlike Conversion Rate
- Matches Per User Distribution

#### Monetization
- Premium vs Free Users Distribution
- Revenue Over Time
- Average Revenue Per User (ARPU)
- Average Revenue Per Paying User (ARPPU)
- Paying Users Count
- Conversion Rate to Premium
- Platform Revenue (iOS vs Android)

#### Retention & Churn
- Retention Cohorts (6-month view)
- Day 1, Day 7, Day 30 Retention Rates
- Churn Rate
- Churned Users Count

#### Top Insights
- Users with Most Matches
- Users with Most Likes Received
- Users with Highest Ranking
- Top Cities by Engagement
- Cities with Highest Match Rate

## Architecture

### Backend Structure

```
app/
├── services/
│   └── analytics_service.rb      # All data aggregation logic
├── controllers/
│   └── analytics_controller.rb   # Request handling and filter parsing
└── views/
    └── analytics/
        ├── index.html.erb         # Main dashboard view
        └── _analytics_script.html.erb  # JavaScript for charts
```

### Service Layer (`analytics_service.rb`)

The AnalyticsService is a class-based service that handles all data aggregation using optimized SQL queries:

- Uses `GROUP BY` for time-series data
- Implements scopes and filters
- Returns aggregated data (never raw user records)
- Uses MySQL-specific date functions for performance

**Key Methods**:
- `apply_filters(scope, filters)` - Apply global filters to any scope
- `new_users_over_time(filters, group_by)` - User registration trends
- `engagement_metrics(filters)` - DAU/WAU/MAU calculations
- `retention_cohorts(filters)` - Cohort analysis
- And many more...

### Controller Layer (`analytics_controller.rb`)

Handles:
- Authentication and admin authorization
- Filter parameter parsing
- Data endpoint routing
- JSON response formatting

**Routes**:
- `GET /analytics` - Main dashboard page
- `GET /analytics/data?section=growth&filters...` - AJAX data endpoint

### Frontend

**Technologies**:
- Chart.js 3.9.1 for data visualization
- Bootstrap 4 for layout
- Font Awesome for icons
- Vanilla JavaScript (no frameworks)

**Chart Types Used**:
- Line charts for time series
- Bar charts for comparisons
- Doughnut charts for distributions
- Custom tables for cohort analysis

## Performance Considerations

### Query Optimization
- All queries use aggregation (`COUNT`, `SUM`, `AVG`, `GROUP BY`)
- Indexes recommended on:
  - `users.created_at`
  - `users.last_sign_in_at`
  - `users.deleted_account`
  - `users.fake_user`
  - `user_match_requests.created_at`
  - `user_match_requests.is_match`
  - `purchases.created_at`

### Caching Strategy
Consider implementing caching for:
- Daily metrics (cache for 1 hour)
- Historical data (cache for 24 hours)
- Filter options (countries/cities list)

Example caching implementation:
```ruby
def growth_data
  Rails.cache.fetch("analytics/growth/#{cache_key}", expires_in: 1.hour) do
    {
      new_users_daily: AnalyticsService.new_users_over_time(@filters, :day),
      # ... other metrics
    }
  end
end

def cache_key
  @filters.to_s.hash
end
```

## Usage

### Accessing the Dashboard

1. Navigate to `/analytics` (requires admin authentication)
2. Use the global filters to customize the view
3. Click "Apply Filters" to refresh all charts
4. Each section loads data independently via AJAX

### Filter Examples

**View last 30 days, real users only, iOS platform**:
- Date Range: Last 30 days
- Bot Filter: Exclude bots
- Device Platform: iOS
- Click Apply Filters

**Compare Premium vs Free users**:
- Set filters for Premium, view metrics
- Note the values
- Change to Free, view metrics
- Compare the differences

### Interpreting Metrics

**DAU/MAU Ratio (Stickiness)**:
- < 10%: Poor engagement
- 10-20%: Average engagement
- 20-30%: Good engagement
- > 30%: Excellent engagement

**Match Conversion Rate**:
- < 1%: Poor matching algorithm
- 1-5%: Average
- 5-10%: Good
- > 10%: Excellent

**Churn Rate**:
- < 5%: Excellent retention
- 5-10%: Good
- 10-20%: Average
- > 20%: Poor, needs improvement

## API Response Format

```json
{
  "new_users_daily": {
    "2024-01-01": 150,
    "2024-01-02": 200
  },
  "user_metrics": {
    "total_users": 10000,
    "real_users": 8500,
    "bot_users": 1000,
    "verified_users": 5000
  }
}
```

## Customization

### Adding New Metrics

1. Add method to `AnalyticsService`:
```ruby
def self.new_metric(filters = {})
  scope = User.where(deleted_account: false)
  scope = apply_filters(scope, filters)
  scope.count
end
```

2. Add to controller data method:
```ruby
def growth_data
  {
    new_metric: AnalyticsService.new_metric(@filters)
  }
end
```

3. Add chart to view:
```html
<canvas id="chart-new-metric"></canvas>
```

4. Add rendering in JavaScript:
```javascript
async function loadGrowthData() {
  const data = await fetchData('growth');
  renderChart('chart-new-metric', data.new_metric);
}
```

### Adding New Filters

1. Add filter to view:
```erb
<select class="form-control" name="new_filter">
  <option value="all">All</option>
  <option value="option1">Option 1</option>
</select>
```

2. Parse in controller:
```ruby
def parse_filters
  @filters[:new_filter] = params[:new_filter] if params[:new_filter].present?
end
```

3. Apply in service:
```ruby
def self.apply_filters(scope, filters)
  scope = scope.where(new_column: filters[:new_filter]) if filters[:new_filter].present?
end
```

## Troubleshooting

### Charts not loading
- Check browser console for JavaScript errors
- Verify Chart.js CDN is accessible
- Ensure AJAX endpoints return valid JSON

### Slow queries
- Check database indexes
- Reduce date range
- Implement caching
- Consider background jobs for heavy calculations

### Incorrect data
- Verify filter parsing in controller
- Check SQL queries in service
- Ensure date ranges are correctly applied
- Validate data types in database

## Future Enhancements

### Recommended Features
1. **Export functionality**: CSV/Excel export of data
2. **Comparison mode**: Compare two date ranges side-by-side
3. **Email reports**: Scheduled analytics reports
4. **Real-time updates**: WebSocket for live metrics
5. **Custom dashboards**: Save filter presets
6. **Drill-down capability**: Click charts to see detailed data
7. **A/B testing metrics**: Track experiment results
8. **Predictive analytics**: ML-based trend forecasting
9. **Alerts**: Set thresholds and get notifications
10. **Mobile responsiveness**: Optimize for mobile devices

### Advanced Analytics
- Funnel analysis (signup → profile completion → first match)
- User journey mapping
- Geographic heat maps
- Time-based patterns (hourly/daily activity)
- Seasonal trends
- Feature adoption metrics

## Security Considerations

- ✅ Admin authentication required
- ✅ No sensitive user data exposed
- ✅ Aggregated data only
- ⚠️ Consider rate limiting on data endpoints
- ⚠️ Add CSRF protection for filter forms
- ⚠️ Implement audit logging for dashboard access

## Maintenance

### Regular Tasks
- Monitor query performance
- Update Chart.js when new versions release
- Review and optimize slow queries
- Clean up old cached data
- Validate data accuracy

### Database Maintenance
```sql
-- Recommended indexes
CREATE INDEX idx_users_created_at ON users(created_at);
CREATE INDEX idx_users_last_sign_in ON users(last_sign_in_at);
CREATE INDEX idx_users_deleted_fake ON users(deleted_account, fake_user);
CREATE INDEX idx_match_requests_created ON user_match_requests(created_at);
CREATE INDEX idx_match_requests_match ON user_match_requests(is_match, match_date);
CREATE INDEX idx_purchases_created ON purchases(created_at);
```

## Support

For questions or issues:
1. Check the troubleshooting section
2. Review the service/controller code
3. Check Rails logs for errors
4. Verify database indexes exist

---

**Version**: 1.0  
**Created**: March 2026  
**Last Updated**: March 2026
