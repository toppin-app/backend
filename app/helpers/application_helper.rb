module ApplicationHelper

	# Helper que nos devuelve un icono de check o cruces si un valor es true o false
	def true_false(value)
	  if value==true
	    "<i class='fa fa-check text-success'></i>".html_safe
	   else
	    "<i class='fa fa-times text-danger'></i>".html_safe
	   end
	end    



	def weekday(weekdays)

		weekdays = weekdays.split(",")

		names = ["","Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado","Domingo"]

		result = ""

		weekdays.each do |w|


	    	result = result + names[w.to_i] + ","

	    end

	    return result.chop
	end

	def black_coffee_review_source_for(venue)
	  latest_item = black_coffee_latest_completed_review_item_for(venue)
	  latest_batch = latest_item&.review_batch
	  latest_batch_reviewed_at = latest_batch&.reviewed_at || latest_item&.reviewed_at || latest_batch&.created_at
	  venue_reviewed_at = venue.reviewed_at if venue.respond_to?(:reviewed_at)
	  current_status = venue.review_status_for_dashboard if venue.respond_to?(:review_status_for_dashboard)

	  if latest_item.present? && current_status.present? && latest_item.review_status != current_status
	    {
	      kind: :manual,
	      label: 'Revision individual',
	      batch: nil,
	      item: nil
	    }
	  elsif venue_reviewed_at.present? && (latest_batch.blank? || latest_batch_reviewed_at.blank? || venue_reviewed_at > latest_batch_reviewed_at + 1.second)
	    {
	      kind: :manual,
	      label: 'Revision individual',
	      batch: nil,
	      item: nil
	    }
	  elsif latest_batch.present?
	    {
	      kind: :batch,
	      label: "Lote ##{latest_batch.id}",
	      batch: latest_batch,
	      item: latest_item
	    }
	  elsif venue_reviewed_at.present?
	    {
	      kind: :manual,
	      label: 'Revision individual',
	      batch: nil,
	      item: nil
	    }
	  else
	    {
	      kind: :none,
	      label: 'Sin revision registrada',
	      batch: nil,
	      item: nil
	    }
	  end
	end

	def black_coffee_latest_completed_review_item_for(venue)
	  items =
	    if venue.association(:review_batch_items).loaded?
	      venue.review_batch_items.to_a
	    else
	      venue.review_batch_items.includes(:review_batch).to_a
	    end

	  items
	    .select { |item| item.review_batch&.completed? }
	    .max_by do |item|
	      timestamp = item.review_batch.reviewed_at || item.reviewed_at || item.updated_at
	      [timestamp&.to_i || 0, item.id.to_i]
	    end
	end

	
end
