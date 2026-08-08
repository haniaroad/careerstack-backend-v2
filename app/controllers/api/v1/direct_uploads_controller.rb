# frozen_string_literal: true

require "base64"
require "digest"
require "stringio"

module Api
  module V1
    class DirectUploadsController < BaseController
      def create
        require_workspace!
        filename = params.require(:filename).to_s
        content_type = params.require(:content_type).to_s
        byte_size = Integer(params.require(:byte_size))
        checksum = params.require(:checksum).to_s

        raise DomainError.new("File exceeds 10 MB limit", code: "validation_error") if byte_size > Tasks::EvidenceLimits::MAX_FILE_BYTES
        unless Tasks::EvidenceLimits::ALLOWED_CONTENT_TYPES.include?(content_type)
          raise DomainError.new("Unsupported file type", code: "validation_error")
        end

        blob = ActiveStorage::Blob.create_before_direct_upload!(
          filename: filename,
          byte_size: byte_size,
          checksum: checksum,
          content_type: content_type
        )

        render json: {
          direct_upload: {
            signed_id: blob.signed_id,
            upload_url: "/api/v1/blob_uploads/#{ERB::Util.url_encode(blob.signed_id)}",
            headers: { "Content-Type" => content_type },
            filename: filename,
            byte_size: byte_size,
            checksum: checksum,
            content_type: content_type
          }
        }, status: :created
      end

      def upload
        require_workspace!
        blob = ActiveStorage::Blob.find_signed(params[:signed_id])
        raise ActiveRecord::RecordNotFound if blob.nil?

        data = request.raw_post
        data = request.body.read if data.blank?
        if data.bytesize != blob.byte_size
          raise DomainError.new("Uploaded file size does not match", code: "validation_error")
        end

        actual_checksum = Base64.strict_encode64(Digest::MD5.digest(data))
        if actual_checksum != blob.checksum
          raise DomainError.new("Uploaded file checksum does not match", code: "validation_error")
        end

        blob.upload(StringIO.new(data))
        head :no_content
      end

      private

      def require_workspace!
        workspace = current_user.resolved_active_workspace
        raise DomainError.new("No active workspace", code: "no_workspace") if workspace.nil?

        workspace
      end
    end
  end
end
