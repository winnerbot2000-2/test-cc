import Foundation

/// Result of uploading a video to a social platform.
struct UploadResult {
    var platform: SocialPlatform
    var success: Bool
    var message: String
    var remoteID: String?
    var remoteURL: String?
}

/// Uploads exported videos to connected platforms as drafts.
/// YouTube: uploaded with privacyStatus = private (draft).
/// TikTok: uploaded with privacy_level = SELF_ONLY (draft).
/// Instagram: Reel published via a public video URL (API requirement).
enum SocialUploader {

    static func upload(
        videoURL: URL,
        title: String,
        platform: SocialPlatform,
        credentials: SocialCredentials,
        accessToken: String,
        asDraft: Bool
    ) async throws -> UploadResult {
        switch platform {
        case .youtube:
            return try await uploadYouTube(videoURL: videoURL, title: title, accessToken: accessToken, asDraft: asDraft)
        case .tiktok:
            return try await uploadTikTok(videoURL: videoURL, title: title, accessToken: accessToken, asDraft: asDraft)
        case .instagram:
            return try await uploadInstagram(title: title, credentials: credentials, accessToken: accessToken)
        }
    }

    // MARK: - YouTube (resumable upload)

    private static func uploadYouTube(videoURL: URL, title: String, accessToken: String, asDraft: Bool) async throws -> UploadResult {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64) ?? 0
        let privacy = asDraft ? "private" : "public"

        let body: [String: Any] = [
            "snippet": [
                "title": title,
                "description": "#Shorts #RPS",
                "categoryId": "22",
                "tags": ["shorts", "rps", "battle"],
            ],
            "status": [
                "privacyStatus": privacy,
                "selfDeclaredMadeForKids": false,
            ],
        ]

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw SocialError.uploadFailed("YouTube rejected the upload request.")
        }

        // Upload the bytes to the resumable session (streamed from disk).
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        let (respData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: videoURL)
        guard let uploadHttp = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHttp.statusCode) else {
            throw SocialError.uploadFailed("YouTube upload failed: \(String(data: respData, encoding: .utf8) ?? "")")
        }
        struct YT: Decodable { let id: String? }
        let yt = try? JSONDecoder().decode(YT.self, from: respData)
        return UploadResult(platform: .youtube, success: true,
                            message: asDraft ? "Uploaded to YouTube as a private draft." : "Published to YouTube.",
                            remoteID: yt?.id,
                            remoteURL: yt?.id.map { "https://youtu.be/\($0)" })
    }

    // MARK: - TikTok (Content Posting API)

    private static func uploadTikTok(videoURL: URL, title: String, accessToken: String, asDraft: Bool) async throws -> UploadResult {
        let fileSize = Int((try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64) ?? 0)
        let privacy = asDraft ? "SELF_ONLY" : "PUBLIC_TO_EVERYONE"

        // 1. Initiate upload.
        let initBody: [String: Any] = [
            "post_info": [
                "title": title,
                "privacy_level": privacy,
                "disable_duet": false,
                "disable_comment": false,
                "disable_stitch": false,
            ],
            "source_info": [
                "source": "FILE_UPLOAD",
                "video_size": fileSize,
                "chunk_size": fileSize,
                "total_chunk_count": 1,
            ],
        ]
        var initRequest = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/post/publish/video/init/")!)
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.httpBody = try JSONSerialization.data(withJSONObject: initBody)
        let (initData, initResponse) = try await URLSession.shared.data(for: initRequest)
        guard let initHttp = initResponse as? HTTPURLResponse,
              (200...299).contains(initHttp.statusCode),
              let json = try? JSONSerialization.jsonObject(with: initData) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let publishID = data["publish_id"] as? String,
              let uploadURLStr = data["upload_url"] as? String,
              let uploadURL = URL(string: uploadURLStr) else {
            throw SocialError.uploadFailed("TikTok init failed: \(String(data: initData, encoding: .utf8) ?? "")")
        }

        // 2. Upload bytes (streamed from disk).
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("bytes 0-\(fileSize - 1)/\(fileSize)", forHTTPHeaderField: "Content-Range")
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: videoURL)
        guard let uploadHttp = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHttp.statusCode) else {
            throw SocialError.uploadFailed("TikTok upload failed: \(String(data: uploadData, encoding: .utf8) ?? "")")
        }

        // 3. Poll status until processing completes or fails.
        var attempts = 0
        while attempts < 30 {
            var statusRequest = URLRequest(url: URL(string: "https://open.tiktokapis.com/v2/post/publish/status/fetch/")!)
            statusRequest.httpMethod = "POST"
            statusRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            statusRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            statusRequest.httpBody = try JSONSerialization.data(withJSONObject: ["publish_id": publishID])
            let (statusData, statusResponse) = try await URLSession.shared.data(for: statusRequest)
            guard let statusHttp = statusResponse as? HTTPURLResponse,
                  (200...299).contains(statusHttp.statusCode),
                  let sjson = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                  let sdata = sjson["data"] as? [String: Any],
                  let status = sdata["status"] as? String else {
                throw SocialError.uploadFailed("TikTok status check failed.")
            }
            if status == "PUBLISH_COMPLETE" {
                return UploadResult(platform: .tiktok, success: true,
                                    message: asDraft ? "Uploaded to TikTok (self-only)." : "Published to TikTok.",
                                    remoteID: publishID)
            }
            if status == "FAILED" {
                throw SocialError.uploadFailed("TikTok reported processing failure: \(sdata["fail_reason"] ?? "")")
            }
            attempts += 1
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw SocialError.uploadFailed("TikTok upload is still processing; check the app for its final status.")
    }

    // MARK: - Instagram (Graph API, Reel via public URL)

    private static func uploadInstagram(title: String, credentials: SocialCredentials, accessToken: String) async throws -> UploadResult {
        let videoURL = credentials.instagramVideoURL
        guard !videoURL.isEmpty else {
            throw SocialError.uploadFailed("Instagram Reels require a public video URL. Set it in Settings → Platforms.")
        }

        // Discover the Instagram business account from the user's pages.
        let igUserID = try await resolveInstagramUserID(accessToken: accessToken)

        // Create media container.
        var createRequest = URLRequest(url: URL(string: "https://graph.facebook.com/v18.0/\(igUserID)/media")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "media_type", value: "REELS"),
            URLQueryItem(name: "video_url", value: videoURL),
            URLQueryItem(name: "caption", value: title),
            URLQueryItem(name: "access_token", value: accessToken),
        ]
        createRequest.httpBody = Data(form.percentEncodedQuery!.utf8)
        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let createHttp = createResponse as? HTTPURLResponse,
              (200...299).contains(createHttp.statusCode),
              let cjson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let creationID = cjson["id"] as? String else {
            throw SocialError.uploadFailed("Instagram container creation failed: \(String(data: createData, encoding: .utf8) ?? "")")
        }

        // Poll the container until the video finishes processing before publishing.
        var attempts = 0
        while attempts < 30 {
            var statusRequest = URLRequest(url: URL(string: "https://graph.facebook.com/v18.0/\(creationID)?fields=status_code")!)
            statusRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (statusData, statusResponse) = try await URLSession.shared.data(for: statusRequest)
            guard let statusHttp = statusResponse as? HTTPURLResponse,
                  (200...299).contains(statusHttp.statusCode),
                  let sjson = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                  let code = sjson["status_code"] as? String else {
                throw SocialError.uploadFailed("Instagram status check failed.")
            }
            if code == "FINISHED" { break }
            if code == "ERROR" {
                throw SocialError.uploadFailed("Instagram media processing failed.")
            }
            attempts += 1
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // Publish.
        var publishRequest = URLRequest(url: URL(string: "https://graph.facebook.com/v18.0/\(igUserID)/media_publish")!)
        publishRequest.httpMethod = "POST"
        publishRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var pform = URLComponents()
        pform.queryItems = [
            URLQueryItem(name: "creation_id", value: creationID),
            URLQueryItem(name: "access_token", value: accessToken),
        ]
        publishRequest.httpBody = Data(pform.percentEncodedQuery!.utf8)
        let (publishData, publishResponse) = try await URLSession.shared.data(for: publishRequest)
        guard let publishHttp = publishResponse as? HTTPURLResponse,
              (200...299).contains(publishHttp.statusCode),
              let pjson = try? JSONSerialization.jsonObject(with: publishData) as? [String: Any],
              let mediaID = pjson["id"] as? String else {
            throw SocialError.uploadFailed("Instagram publish failed: \(String(data: publishData, encoding: .utf8) ?? "")")
        }
        return UploadResult(platform: .instagram, success: true,
                            message: "Published as an Instagram Reel.",
                            remoteID: mediaID)
    }

    private static func resolveInstagramUserID(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://graph.facebook.com/v18.0/me/accounts?fields=instagram_business_account,id,name")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = json["data"] as? [[String: Any]] else {
            throw SocialError.uploadFailed("Could not read Instagram business accounts. Link a business/creator account to a Facebook Page.")
        }
        for page in pages {
            if let ig = page["instagram_business_account"] as? [String: Any], let id = ig["id"] as? String {
                return id
            }
        }
        throw SocialError.uploadFailed("No Instagram business account found on your Pages.")
    }
}
