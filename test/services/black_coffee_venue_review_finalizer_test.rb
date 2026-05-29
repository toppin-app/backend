require 'test_helper'

class BlackCoffeeVenueReviewFinalizerTest < ActiveSupport::TestCase
  test 'normalizes category corrections as approved category change decisions' do
    finalizer = BlackCoffeeVenueReviewFinalizer.new(
      batch: nil,
      reviewer: nil,
      rejections: {
        'ven_1' => {
          reason: 'wrong_category',
          correct_category: '1',
          corrected_category: 'cafeteria'
        },
        'ven_2' => {
          reason: 'bad_photos'
        }
      }
    )

    decisions = finalizer.send(:normalize_decisions)

    assert_equal :correct_category, decisions['ven_1'][:action]
    assert_equal 'wrong_category', decisions['ven_1'][:reason]
    assert_equal 'cafeteria', decisions['ven_1'][:corrected_category]
    assert_equal :reject, decisions['ven_2'][:action]
    assert_equal 'bad_photos', decisions['ven_2'][:reason]
  end

  test 'raises clearly when a requested category correction has an invalid category' do
    finalizer = BlackCoffeeVenueReviewFinalizer.new(
      batch: nil,
      reviewer: nil,
      rejections: {
        'ven_1' => {
          reason: 'wrong_category',
          correct_category: '1',
          corrected_category: 'no_existe'
        }
      }
    )

    error = assert_raises(ArgumentError) { finalizer.send(:normalize_decisions) }

    assert_includes error.message, 'Categoria corregida no valida'
  end
end
