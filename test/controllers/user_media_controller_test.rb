require 'test_helper'
require 'tmpdir'
require_relative '../support/t03_boundary_helpers'

class UserMediaControllerTest < ActionDispatch::IntegrationTest
  include T03BoundaryHelpers
  self.fixture_table_names = []

  setup do
    @owner = create_boundary_user
    @other = create_boundary_user
    @medium = UserMedium.create!(user: @owner)
  end

  test 'anonymous CRUD requests cannot read or change media' do
    assert_no_difference('UserMedium.count') do
      get user_medium_url(@medium), as: :json
      assert_response :unauthorized
      post user_media_url, params: { user_medium: { user_id: @owner.id } }, as: :json
      assert_response :unauthorized
      patch user_medium_url(@medium), params: { user_medium: { position: 7 } }, as: :json
      assert_response :unauthorized
      delete user_medium_url(@medium), as: :json
      assert_response :unauthorized
    end
    assert_equal 0, @medium.reload.position
  end

  test 'invalid expired and revoked JWTs cannot delete media' do
    [{ 'Authorization' => 'Bearer not-a-token' },
     authorization_for(@owner, exp: 1.second.ago.to_i),
     authorization_for(@owner, jti: 'revoked-test-jti')].each do |headers|
      assert_no_difference('UserMedium.count') do
        delete user_medium_url(@medium), headers: headers, as: :json
      end
      assert_response :unauthorized
    end
  end

  test 'blocked accounts cannot update media' do
    @owner.update!(blocked: true)
    patch user_medium_url(@medium), params: { user_medium: { position: 7 } },
          headers: authorization_for(@owner), as: :json
    assert_response :unauthorized
    assert_equal 0, @medium.reload.position
  end

  test 'owner can read its media JSON' do
    get user_medium_url(@medium), headers: authorization_for(@owner), as: :json
    assert_response :ok
    assert_equal @medium.id, response.parsed_body['id']
    assert_equal @owner.id, response.parsed_body['user_id']
  end

  test 'owner can create another media record with a server assigned position' do
    assert_difference('UserMedium.count', 1) do
      post user_media_url, params: { user_medium: { user_id: @owner.id, position: 999 } },
           headers: authorization_for(@owner), as: :json
    end
    assert_response :created
    created = @owner.user_media.find_by(position: 1)
    assert_not_nil created
    assert_includes response.parsed_body.map { |record| record['id'] }, created.id
  end

  test 'owner can upload a moderated image and deletion removes the stored file' do
    with_upload_root do
      with_moderation_boundary(bytes: Base64.decode64(test_image.split(',').last)) do
        post user_media_url, params: { user_medium: { user_id: @owner.id, file: test_image } },
             headers: authorization_for(@owner), as: :json
      end
      assert_response :created
      uploaded = @owner.user_media.find_by!(position: 1)
      stored_path = uploaded.file.path
      assert File.file?(stored_path)
      assert uploaded.file.thumb.file.exists?

      delete user_medium_url(uploaded), headers: authorization_for(@owner), as: :json
      assert_response :no_content
      assert_not File.exist?(stored_path)
      assert_not UserMedium.exists?(uploaded.id)
    end
  end

  test 'a missing user association prevents media creation' do
    assert_no_difference('UserMedium.count') do
      post user_media_url, params: { user_medium: { user_id: 0 } },
           headers: authorization_for(@owner), as: :json
    end
    assert_response :unprocessable_entity
    assert response.parsed_body.key?('user')
  end

  test 'owner can change the persisted media position' do
    patch user_medium_url(@medium), params: { user_medium: { position: 7 } },
          headers: authorization_for(@owner), as: :json
    assert_response :ok
    assert_equal 7, @medium.reload.position
    assert_equal 7, response.parsed_body['position']
  end

  test 'owner can delete its media record' do
    assert_difference('UserMedium.count', -1) do
      delete user_medium_url(@medium), headers: authorization_for(@owner), as: :json
    end
    assert_response :no_content
    assert_not UserMedium.exists?(@medium.id)
  end

  test 'admin can delete a user media record' do
    admin = create_boundary_user(admin: true)
    assert_difference('UserMedium.count', -1) do
      delete user_medium_url(@medium), headers: authorization_for(admin), as: :json
    end
    assert_response :no_content
    assert_not UserMedium.exists?(@medium.id)
  end

  # T35: these demonstrate missing ownership checks and client-selected owners.
  # They characterize a known vulnerability, not an accepted authorization rule.
  test 'T35 characterization a third party can read another users media' do
    get user_medium_url(@medium), headers: authorization_for(@other), as: :json
    assert_response :ok
    assert_equal @owner.id, response.parsed_body['user_id']
  end

  test 'T35 characterization a third party can update another users media' do
    patch user_medium_url(@medium), params: { user_medium: { position: 9 } },
          headers: authorization_for(@other), as: :json
    assert_response :ok
    assert_equal 9, @medium.reload.position
  end

  test 'T35 characterization a third party can delete another users media' do
    assert_difference('UserMedium.count', -1) do
      delete user_medium_url(@medium), headers: authorization_for(@other), as: :json
    end
    assert_response :no_content
    assert_not UserMedium.exists?(@medium.id)
  end

  test 'T35 characterization create accepts a different client supplied user_id' do
    assert_difference('UserMedium.count', 1) do
      post user_media_url, params: { user_medium: { user_id: @owner.id } },
           headers: authorization_for(@other), as: :json
    end
    assert_response :created
    assert_equal 2, @owner.user_media.count
    assert_empty response.parsed_body
  end

  test 'T35 characterization update can transfer media ownership' do
    patch user_medium_url(@medium), params: { user_medium: { user_id: @other.id } },
          headers: authorization_for(@other), as: :json
    assert_response :ok
    assert_equal @other.id, @medium.reload.user_id
  end

  test 'moderation rejects explicit nudity before a media record is saved' do
    label = Aws::Rekognition::Types::ModerationLabel.new(name: 'Explicit Nudity', confidence: 99.0)
    with_moderation_boundary(labels: [label]) do
      assert_no_difference('UserMedium.count') do
        post user_media_url, params: {
          user_medium: { user_id: @owner.id, file: 'data:image/png;base64,cGhvdG8tdGVzdA==' }
        }, headers: authorization_for(@owner), as: :json
      end
    end
    assert_response :bad_request
  end

  test 'a moderation provider failure cannot save an unchecked image' do
    with_moderation_boundary(failure: IOError.new('synthetic moderation outage')) do
      assert_no_difference('UserMedium.count') do
        assert_raises(IOError) do
          post user_media_url, params: {
            user_medium: { user_id: @owner.id, file: 'data:image/png;base64,cGhvdG8tdGVzdA==' }
          }, headers: authorization_for(@owner), as: :json
        end
      end
    end
  end

  test 'an update with explicit nudity removes the newly stored image' do
    label = Aws::Rekognition::Types::ModerationLabel.new(name: 'Explicit Nudity', confidence: 99.0)
    with_upload_root do
      with_moderation_boundary(labels: [label], bytes: Base64.decode64(test_image.split(',').last)) do
        patch user_medium_url(@medium), params: { user_medium: { file: test_image } },
              headers: authorization_for(@owner), as: :json
      end
      assert_response :bad_request
      assert_nil @medium.reload.file.file
      assert_empty Dir.glob(File.join(CarrierWave.root, 'uploads', '**', '*')).select { |path| File.file?(path) }
    end
  end

  # Current reliability/security boundary: update persists before moderation.
  # This passing characterization must not be read as approving unchecked files.
  test 'characterization a moderation failure during update leaves the new image stored' do
    with_upload_root do
      with_moderation_boundary(failure: IOError.new('synthetic moderation outage')) do
        assert_raises(IOError) do
          patch user_medium_url(@medium), params: { user_medium: { file: test_image } },
                headers: authorization_for(@owner), as: :json
        end
      end
      assert File.file?(@medium.reload.file.path)
    end
  end

  private

  def with_moderation_boundary(labels: [], failure: nil, bytes: 'photo-test')
    result = Aws::Rekognition::Types::DetectModerationLabelsResponse.new(
      moderation_labels: labels, moderation_model_version: 'test-model'
    )
    client = Object.new
    client.define_singleton_method(:detect_moderation_labels) do |request|
      raise failure if failure
      raise 'Image bytes were not forwarded' unless request[:image][:bytes] == bytes
      result
    end
    Aws::Rekognition::Client.stub(:new, client) { yield }
  end

  def test_image
    # Hand-authored one pixel GIF; no personal image or external asset is used.
    'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
  end

  def with_upload_root
    previous_root = CarrierWave.root
    Dir.mktmpdir('toppin-media-test-') do |directory|
      CarrierWave.root = directory
      yield
    end
  ensure
    CarrierWave.root = previous_root
  end
end
