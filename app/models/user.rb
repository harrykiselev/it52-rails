# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  email                  :string(255)      default(""), not null
#  encrypted_password     :string(128)      default(""), not null
#  password_salt          :string(255)      default(""), not null
#  created_at             :datetime
#  updated_at             :datetime
#  reset_password_token   :string(255)
#  nickname               :string(255)      default("")
#  role                   :integer
#  first_name             :string(255)
#  last_name              :string(255)
#  bio                    :text
#  avatar_image           :string(255)
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  sign_in_count          :integer          default(0), not null
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :inet
#  last_sign_in_ip        :inet
#  confirmation_token     :string(255)
#  confirmed_at           :datetime
#  confirmation_sent_at   :datetime
#  unconfirmed_email      :string(255)
#  slug                   :string(255)
#  website                :string(255)
#

class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable and
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
         :trackable, :validatable, :confirmable, :omniauthable

  enum role: [ :member, :admin ]

  has_many :authentications, dependent: :destroy
  accepts_nested_attributes_for :authentications

  has_many :owner_of_events, class_name: 'Event', foreign_key: 'organizer_id'
  has_many :event_participations
  has_many :member_in_events, class_name: 'Event', through: :event_participations, source: :event

  before_create :assign_default_role, if: -> { role.nil? }
  before_validation :normalize_url, if: :website_changed?

  validates :website, format: { with: URI::regexp(%w(http https)) }, allow_nil: true

  extend FriendlyId
  friendly_id :slug_candidates, use: :slugged

  mount_uploader :avatar_image, UserAvatarUploader

  def full_name
    [first_name, last_name].compact.join(' ').presence || nickname.presence || email
  end

  def to_s
    full_name
  end

  def slug_candidates
    [
      :nickname,
      [:first_name, :last_name],
    ]
  end

  def should_generate_new_friendly_id?
    nickname_changed? || super
  end

  def self.new_with_session(params, session)
    super.tap do |user|
      if data = session["devise.oauth_data"]
        user = from_omniauth data
      end
    end
  end

  def self.from_omniauth(auth, current_user = nil)
    authentication = Authentication.where(provider: auth[:provider], uid: auth[:uid]).
                                    first_or_initialize.set_attributes_from_omniauth(auth)

    user = current_user || authentication.user
    user ||= where(email: auth['info']['email']).first_or_create

    user.authentications << authentication unless user.has_identity? auth[:provider]
    user.skip_confirmations! if user.confirmed? || !user.email_required?
    user = UpdateUserFromOmniauth.new(user, auth[:provider], auth[:info]).set_attributes
    user.save
    user
  end

  def skip_confirmations!
    self.skip_confirmation!
    self.skip_reconfirmation!
  end

  def has_identity?(provider)
    provider.in? authentications.map(&:provider)
  end

  def unlinked_providers
    self.class.omniauth_providers.map(&:to_s) - authentications.pluck(:provider)
  end

  def password_required?
    super && authentications.blank?
  end

  def email_required?
    super && authentications.blank?
  end

  private

  def normalize_url
    self.website = if result = website.to_url
      result
    else
      website
    end
  end

  def assign_default_role
    self.role = :member
  end
end
