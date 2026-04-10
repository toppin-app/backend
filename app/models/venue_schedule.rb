class VenueSchedule < ApplicationRecord
  belongs_to :venue

  validates :day, presence: true, inclusion: { in: Venue::DAY_ORDER }
  validates :slot_index, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validate :slot_presence_for_open_day

  def opening_time
    slot_open&.strftime('%H:%M')
  end

  def closing_time
    slot_close&.strftime('%H:%M')
  end

  private

  def slot_presence_for_open_day
    return if closed?

    if slot_open.blank? || slot_close.blank?
      errors.add(:base, 'Los dias abiertos deben tener hora de apertura y cierre')
    end
  end
end
