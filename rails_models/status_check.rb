class StatusCheck < ActiveRecord::Base
  belongs_to :user

  def self.user_status(current_user)
    if !StatusCheck.where(:user_id => current_user.id).empty?
      StatusCheck.where(:user_id => current_user.id).first
    else
      StatusCheck.create(user: current_user)
    end
  end

end