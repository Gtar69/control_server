class Product < ActiveRecord::Base

  has_many :photos
  has_many :game_datas
  has_many :user, :through => :game_datas
  belongs_to :category
  belongs_to :platform
  has_one :zooti_game
  accepts_nested_attributes_for :photos
  validates_presence_of :name
  serialize :back_up_entries
  serialize :back_up_remove_entries
  serialize :player_waiting_queue, Array
  scope :allow_played, -> { where(:allow_play => true) }

  def default_photo
    photos.first
  end


  def status
    if can_play_now?
      "activated"
    else
      "busy"
    end
  end

  def can_play_now?
    can_play_now = false
    Servernode.available.each do |node|
      if node.can_play?(self)
        can_play_now = true
        break
      else
        next
      end
    end
    can_play_now
  end

  def refresh_player_waiting_queue
    player_waiting_queue.clear
    Servernode.all.each do |node|
      break_all = false
      if node.available? && node.can_play?(self)
        # [0]:  player doesn't need to wait
        update_attribute(:player_waiting_queue, [0])
        break_all = true
      elsif !node.available? && node.can_play?(self) #&&  (node.product_id == id)
        player_waiting_queue << node.player
        save
      else

      end
      break if break_all
    end
  end


end