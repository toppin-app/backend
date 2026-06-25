require 'test_helper'

class VenueCategoryGeographyTest < ActiveSupport::TestCase
  test 'festivals are treated as non-geographic so they are not proximity filtered' do
    assert Venue.non_geographic_category?('festival')
    assert Venue.non_geographic_category?('FESTIVAL')
    assert Venue.non_geographic_category?(' festival ')
  end

  test 'local categories remain geographic' do
    assert_not Venue.non_geographic_category?('restaurante')
    assert_not Venue.non_geographic_category?('cafeteria')
    assert_not Venue.non_geographic_category?('nightlife')
  end

  test 'blank or unknown categories are not treated as non-geographic' do
    assert_not Venue.non_geographic_category?(nil)
    assert_not Venue.non_geographic_category?('')
    assert_not Venue.non_geographic_category?('all')
  end
end
