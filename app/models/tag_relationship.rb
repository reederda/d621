class TagRelationship < ApplicationRecord
  self.abstract_class = true

  SUPPORT_HARD_CODED = true

  belongs_to_creator
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :forum_post, optional: true
  belongs_to :forum_topic, optional: true
  belongs_to :antecedent_tag, class_name: "Tag", foreign_key: "antecedent_name", primary_key: "name", default: -> { Tag.find_or_create_by_name(antecedent_name) }
  belongs_to :consequent_tag, class_name: "Tag", foreign_key: "consequent_name", primary_key: "name", default: -> { Tag.find_or_create_by_name(consequent_name) }
  has_one :antecedent_wiki, through: :antecedent_tag, source: :wiki_page
  has_one :consequent_wiki, through: :consequent_tag, source: :wiki_page

  scope :active, ->{approved}
  scope :approved, ->{where(status: %w[active processing queued])}
  scope :deleted, ->{where(status: "deleted")}
  scope :pending, ->{where(status: "pending")}
  scope :retired, ->{where(status: "retired")}
  scope :duplicate_relevant, ->{where(status: %w[active processing queued pending])}

  before_validation :initialize_creator, :on => :create
  before_validation :normalize_names
  validates :status, format: { :with => /\A(active|deleted|pending|processing|queued|retired|error: .*)\Z/ }
  validates :creator_id, :antecedent_name, :consequent_name, presence: true
  validates :creator, presence: { message: "must exist" }, if: -> { creator_id.present? }
  validates :approver, presence: { message: "must exist" }, if: -> { approver_id.present? }
  validates :forum_topic, presence: { message: "must exist" }, if: -> { forum_topic_id.present? }
  validate :validate_creator_is_not_limited, on: :create
  validates :antecedent_name, tag_name: { disable_ascii_check: true }, on: :create
  validates :consequent_name, tag_name: true, on: :create
  validate :antecedent_and_consequent_are_different

  def initialize_creator
    self.creator_id = CurrentUser.user.id
    self.creator_ip_addr = CurrentUser.ip_addr
  end

  def normalize_names
    self.antecedent_name = antecedent_name.downcase.tr(" ", "_")
    self.consequent_name = consequent_name.downcase.tr(" ", "_")
  end

  def validate_creator_is_not_limited
    allowed = creator.can_suggest_tag_with_reason
    if allowed != true
      errors.add(:creator, User.throttle_reason(allowed))
      return false
    end
    true
  end

  def is_approved?
    status.in?(%w[active processing queued])
  end

  def is_retired?
    status == "retired"
  end

  def is_deleted?
    status == "deleted"
  end

  def is_pending?
    status == "pending"
  end

  def is_active?
    status == "active"
  end

  def is_errored?
    status =~ /\Aerror:/
  end

  def deletable_by?(user)
    return true if user.is_moderator?
    return false
  end

  def editable_by?(user)
    deletable_by?(user)
  end

  module SearchMethods
    def name_matches(name)
      where("(antecedent_name like ? escape E'\\\\' or consequent_name like ? escape E'\\\\')", name.downcase.to_escaped_for_sql_like, name.downcase.to_escaped_for_sql_like)
    end

    def status_matches(status)
      status = status.downcase

      if status == "approved"
        where(status: %w[active processing queued])
      else
        where(status: status)
      end
    end

    def for_creator(id)
      where("creator_id = ?", id)
    end

    def tag_matches(field, params)
      return all if params.blank?
      where(field => Tag.search(params).reorder(nil).select(:name))
    end

    def pending_first
      # unknown statuses return null and are sorted first
      order(Arel.sql("array_position(array['queued', 'processing', 'pending', 'active', 'deleted', 'retired'], status::text) NULLS FIRST, antecedent_name, consequent_name"))
    end

    def default_order
      pending_first
    end

    def search(params)
      q = super

      if params[:name_matches].present?
        q = q.name_matches(params[:name_matches])
      end

      if params[:antecedent_name].present?
        # Split at both space and , to preserve backwards compatibility
        q = q.where(antecedent_name: params[:antecedent_name].split(/[ ,]/).first(100))
      end

      if params[:consequent_name].present?
        q = q.where(consequent_name: params[:consequent_name].split(/[ ,]/).first(100))
      end

      if params[:status].present?
        q = q.status_matches(params[:status])
      end

      if params[:antecedent_tag_category].present?
        q = q.joins(:antecedent_tag).where("tags.category": params[:antecedent_tag_category])
      end

      if params[:consequent_tag_category].present?
        q = q.joins(:consequent_tag).where("tags.category": params[:consequent_tag_category])
      end

      if params[:creator_name].present?
        q = q.where("creator_id = ?", User.name_to_id(params[:creator_name]))
      end

      if params[:approver_name].present?
        q = q.where("approver_id = ?", User.name_to_id(params[:approver_name]))
      end

      # Legacy params?
      q = q.tag_matches(:antecedent_name, params[:antecedent_tag])
      q = q.tag_matches(:consequent_name, params[:consequent_tag])

      if params[:category].present?
        q = q.joins(:consequent_tag).where("tags.category": params[:category].split)
      end

      case params[:order]
      when "created_at"
        q = q.order("created_at desc nulls last, id desc")
      when "updated_at"
        q = q.order("updated_at desc nulls last, id desc")
      when "name"
        q = q.order("antecedent_name asc, consequent_name asc")
      when "tag_count"
        q = q.joins(:consequent_tag).order("tags.post_count desc, antecedent_name asc, consequent_name asc")
      else
        q = q.apply_default_order(params)
      end

      q
    end
  end

  module MessageMethods
    def relationship
      # "TagAlias" -> "tag alias", "TagImplication" -> "tag implication"
      self.class.name.underscore.tr("_", " ")
    end

    def approval_message(approver)
      "The #{relationship} [[#{antecedent_name}]] -> [[#{consequent_name}]] #{forum_link} has been approved by @#{approver.name}."
    end

    def failure_message(e = nil)
      "The #{relationship} [[#{antecedent_name}]] -> [[#{consequent_name}]] #{forum_link} failed during processing. Reason: #{e}"
    end

    def reject_message(rejector)
      "The #{relationship} [[#{antecedent_name}]] -> [[#{consequent_name}]] #{forum_link} has been rejected by @#{rejector.name}."
    end

    def retirement_message
      "The #{relationship} [[#{antecedent_name}]] -> [[#{consequent_name}]] #{forum_link} has been retired."
    end

    def date_timestamp
      Time.now.strftime("%Y-%m-%d")
    end

    def forum_link
      "(forum ##{forum_post.id})" if forum_post.present?
    end
  end

  concerning :EmbeddedText do
    class_methods do
      def embedded_pattern
        raise NotImplementedError
      end
    end
  end

  def antecedent_and_consequent_are_different
    if antecedent_name == consequent_name
      errors.add(:base, "Cannot alias or implicate a tag to itself")
    end
  end

  def estimate_update_count
    Post.fast_count(antecedent_name, skip_cache: true)
  end

  def update_posts
    Post.without_timeout do
      Post.sql_raw_tag_match(antecedent_name).find_each do |post|
        post.with_lock do
          CurrentUser.scoped(creator, creator_ip_addr) do
            post.do_not_version_changes = true
            post.tag_string += " "
            post.save!
          end
        end
      end
    end
  end

  extend SearchMethods
  include MessageMethods
end
