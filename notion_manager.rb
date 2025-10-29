require 'net/http'
require 'uri'
require 'json'
require 'time'

# ---------------------------------------------------
# 認証情報読込み
# ---------------------------------------------------
account_hash = csv_to_hash('settings/account_settings.csv')
NOTION_API_KEY = account_hash["notion_api_key"]
DATABASE_ID = account_hash["database_id"]
PAGE_ID = account_hash["page_id"]

#--------------------------------------
# Notionデータベース操作クラス
#--------------------------------------
class NotionManager
  def initialize(logger)
    @api_key = NOTION_API_KEY
    @database_id = DATABASE_ID
    @logger = logger
    @headers = {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json',
      'Notion-Version' => '2022-06-28'
    }
  end

  #--------------------------------------
  # パブリックメソッド：開始実績とステータス更新
  #--------------------------------------
  def update_start_status(start_actual_time, status)
    @logger.info("Updating start status for page: #{PAGE_ID}")
    @logger.debug("Start time: #{start_actual_time}, Status: #{status}")

    update_notion_page({
      "開始実績" => { date: { start: utc_to_jst(start_actual_time) } },
      "ステータス" => { select: { name: status } }
    })
  end

  #--------------------------------------
  # パブリックメソッド：終了実績とステータス更新
  #--------------------------------------
  def update_end_status(end_actual_time, status)
    @logger.info("Updating end status for page: #{PAGE_ID}")
    @logger.debug("End time: #{end_actual_time}, Status: #{status}")

    update_notion_page({
      "終了実績" => { date: { start: utc_to_jst(end_actual_time) } },
      "ステータス" => { select: { name: status } }
    })
  end

  #--------------------------------------
  # パブリックメソッド：終了実績とステータスとエラー内容を更新
  #--------------------------------------
  def update_end_status_with_error(end_actual_time, status, error_message)
    @logger.info("Updating end status and error message for page: #{PAGE_ID}")
    @logger.debug("End time: #{end_actual_time}, Status: #{status}, Error: #{error_message}")

    update_notion_page({
      "終了実績" => { date: { start: utc_to_jst(end_actual_time) } },
      "ステータス" => { select: { name: status } },
      "エラー内容" => { rich_text: [{ text: { content: error_message } }] }
    })
  end

  private

  #--------------------------------------
  # プライベートメソッド：Notionページ更新
  #--------------------------------------
  def update_notion_page(properties)
    uri = URI("https://api.notion.com/v1/pages/#{PAGE_ID}")
    body = { properties: properties }.to_json
    max_retries = 3
    retry_count = 0

    begin
      request = Net::HTTP::Patch.new(uri, @headers)
      request.body = body
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      @logger.info("Status update completed with response code: #{response.code}")
      @logger.debug("Response body: #{response.body}")

      unless response.code == "200"
        raise "HTTP request failed with response code: #{response.code}, body: #{response.body}"
      end

      response.body
    rescue StandardError => e
      retry_count += 1
      if retry_count >= max_retries
        @logger.error("Failed to update status after #{max_retries} attempts: #{e.message}")
        raise "Failed to update Notion page after #{max_retries} attempts: #{e.message}"
      end

      @logger.warn("Error updating app status (attempt #{retry_count}/#{max_retries}): #{e.message}")
      sleep(2)  # リトライ前に2秒待機
      retry
    end
  end

  #--------------------------------------
  # プライベートメソッド：時間変換ユーティリティ
  #--------------------------------------
  def jst_to_utc(time_str)
    time = Time.parse(time_str + " +09:00")  # JSTであることを明示
    utc_time = time.getutc
    utc_time.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  end

  def utc_to_jst(time_str)
    time = Time.parse(time_str)
    jst_time = time.getlocal("+09:00")
    jst_time.strftime("%Y-%m-%dT%H:%M:%S+09:00")
  end
end