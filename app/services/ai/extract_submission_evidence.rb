# frozen_string_literal: true

module Ai
  class ExtractSubmissionEvidence
    MAX_TEXT_CHARS = 12_000
    MAX_PDF_PAGES = 30

    Result = Struct.new(:text_parts, :unsupported_items, :image_blobs, :analysis_incomplete, keyword_init: true)

    def self.call(submission:)
      new(submission: submission).call
    end

    def initialize(submission:)
      @submission = submission
    end

    def call
      parts = []
      unsupported = []
      images = []

      if @submission.body.present?
        parts << "Submission text:\n#{@submission.body.to_s.truncate(MAX_TEXT_CHARS)}"
      end

      @submission.links.each do |link|
        unsupported << { "kind" => "url", "label" => link.url, "reason" => "arbitrary_url_not_analyzed" }
      end

      @submission.files.each do |attachment|
        blob = attachment.blob
        content_type = blob.content_type.to_s

        if content_type.start_with?("image/")
          if Tasks::EvidenceLimits.analyzable?(content_type)
            images << blob
            parts << "Image attachment present: #{blob.filename} (#{content_type})"
          else
            unsupported << item_for_blob(blob, "image_type_not_analyzed")
          end
          next
        end

        unless Tasks::EvidenceLimits.analyzable?(content_type)
          unsupported << item_for_blob(blob, "file_type_not_analyzed")
          next
        end

        extracted = extract_with_cache(blob)
        if extracted[:ok]
          parts << "File #{blob.filename}:\n#{extracted[:text].to_s.truncate(MAX_TEXT_CHARS)}"
        else
          unsupported << item_for_blob(blob, extracted[:error] || "extraction_failed")
        end
      end

      Result.new(
        text_parts: parts,
        unsupported_items: unsupported,
        image_blobs: images,
        analysis_incomplete: unsupported.any?
      )
    end

    private

    def item_for_blob(blob, reason)
      {
        "kind" => "file",
        "label" => "#{blob.filename} (#{blob.content_type})",
        "reason" => reason
      }
    end

    def extract_with_cache(blob)
      digest = blob.checksum.presence || Digest::SHA256.hexdigest("#{blob.key}:#{blob.byte_size}")
      cached = AiExtractionCache.find_by(blob_digest: digest)
      if cached
        return { ok: true, text: cached.extracted_text } if cached.status == AiExtractionCache::STATUS_SUCCEEDED

        return { ok: false, error: cached.error_code || "extraction_failed" }
      end

      text = extract_text(blob)
      AiExtractionCache.create!(
        blob_digest: digest,
        content_type: blob.content_type,
        extracted_text: text,
        status: AiExtractionCache::STATUS_SUCCEEDED
      )
      { ok: true, text: text }
    rescue StandardError => e
      Rails.logger.warn({ event: "ai_extraction_failed", content_type: blob.content_type, error_class: e.class.name }.to_json)
      AiExtractionCache.find_or_initialize_by(blob_digest: digest).update!(
        content_type: blob.content_type,
        status: AiExtractionCache::STATUS_FAILED,
        error_code: "extraction_failed"
      )
      { ok: false, error: "extraction_failed" }
    end

    def extract_text(blob)
      case blob.content_type
      when "text/plain"
        blob.download.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).truncate(MAX_TEXT_CHARS)
      when "application/pdf"
        extract_pdf(blob)
      when "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        extract_docx(blob)
      else
        ""
      end
    end

    def extract_pdf(blob)
      require "pdf-reader"
      io = StringIO.new(blob.download)
      reader = PDF::Reader.new(io)
      pages = reader.pages.first(MAX_PDF_PAGES).map(&:text).join("\n")
      pages.to_s.truncate(MAX_TEXT_CHARS)
    end

    def extract_docx(blob)
      require "zip"
      xml = nil
      Zip::File.open_buffer(StringIO.new(blob.download)) do |zip|
        entry = zip.find_entry("word/document.xml")
        xml = entry.get_input_stream.read if entry
      end
      return "" if xml.blank?

      xml.to_s.gsub(%r{</w:p>}, "\n").gsub(%r{<[^>]+>}, " ").squeeze(" ").strip.truncate(MAX_TEXT_CHARS)
    end
  end
end
