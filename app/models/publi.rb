class Publi < ApplicationRecord
	  mount_uploader :image, ImageUploader
	  mount_uploader :video, ImageUploader
		has_many :user_publis, dependent: :destroy
		has_many :viewers, through: :user_publis, source: :user
	  scope :active_date, -> { where("start_date < ? AND end_date > ?", DateTime.now, DateTime.now) }
	  scope :active_time, -> { where("start_time < NOW() AND end_time > NOW()") }


	  def image_complete
	  	 return "https://app.toppin.es"+self.image.thumb.url if self.image?
	  	 return "https://app.toppin.es"+self.video.url if self.video?
	  end


	  def self.active_now

	  	publis = Publi.all.active_date.active_time.order(repeat_swipes: :asc)

	  	result = []

	  	publis.each do |publi|

	  		if publi.check_weekday(Date.today.strftime("%u"))
	   			result << publi
	   		end

	  	end

	  	return result

	  end




	  # Nos dice si el weekday está en el array de la publi.
	  def check_weekday(weekday)
			weekdays = self.weekdays.split(",")
 			return weekdays.include? weekday.to_s
   	  end

end
