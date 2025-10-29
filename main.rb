require "./file_create.rb"
require "./scraper.rb"
require "./notion_manager.rb"

# ---------------------------------------------------
# 過去ログ削除 & 新規ログ作成
# ---------------------------------------------------
remove_old_logs_if_needed('logs', 10)
time = Time.now.strftime("%Y%m%d%H%M%S")
log_filename = "logs/log_#{time}.log"
logger = Logger.new(log_filename)

# ---------------------------------------------------
# バージョン宣言 2.1.1: Notion通知を追加
# 履歴
# v2.1. 商品画像と商品名を取得する仕様を追加
# v2.0: セールバリエーションのみ取得する仕様
# v1.1: セール商品以外もすべて取得する仕様に変更
# ---------------------------------------------------
log_message = "==================== nike_research_v2.1.1 ===================="
logger.info(log_message)

log_message = "==================== リサーチ処理を開始 ===================="
log_info_message(log_message, logger)

# ---------------------------------------------------
# 稼働開始通知 
# ---------------------------------------------------
notion_notify = NotionManager.new(logger)
start_actual_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
notion_notify.update_start_status(start_actual_time, "稼働中")

# ---------------------------------------------------
# 認証情報の読込み
# ---------------------------------------------------
# Google Spreadsheet
session = GoogleDrive::Session.from_config('settings/config.json')
account_settings = csv_to_hash('settings/account_settings.csv')
sp_key = account_settings["spreadsheet_key"]

# ---------------------------------------------------
# Driver起動
# ---------------------------------------------------
driver, wait = start_up_selenium()

# ---------------------------------------------------
# スプレッドシートのタイトル一覧読込み
# ---------------------------------------------------
sp = session.spreadsheet_by_key(sp_key)
sp_titles = sp.worksheets.map(&:title)

# ---------------------------------------------------
# シート毎にリサーチ処理
# ---------------------------------------------------
begin
	sp_titles.each_with_index do |sp_title, i|
		begin
			log_message = "=> シート.#{i+1}: #{sp_title}"
			log_info_message(log_message, logger)

			sheet = sp.worksheet_by_title(sp_title)

			# B1セルの値がURLの形式でない場合はスキップ
			nike_list_url = sheet["B1"]
			unless nike_list_url =~ URI::DEFAULT_PARSER.make_regexp
				log_message = "==> B1セルの値がURL形式でないため、処理をスキップします."
				log_info_message(log_message, logger)
				log_message = "------------------------------------------------------------"
				log_info_message(log_message, logger)
				next
			end

			# NIKE商品一覧URLから全商品取得
			nike_item_datas = scrape_nike_list_page(driver, wait, nike_list_url, logger)
			if nike_item_datas.empty?
				log_message = "==> NIKE商品URLが取得できなかったため、処理をスキップします."
				log_info_message(log_message, logger)
				log_message = "------------------------------------------------------------"
				log_info_message(log_message, logger)
				next
			end

			create_process_csv("process")
			nike_item_datas.each do |nike_item_data|
				data = [nike_item_data[:item_url], nike_item_data[:item_title].sjisable, nike_item_data[:item_img_url], nike_item_data[:acquired_status], nike_item_data[:item_vari_num_text], nike_item_data[:item_vari_img_ids]]
				update_process_csv("process", data)
			end
			item_num = nike_item_datas.size
			log_info_message("  => 該当商品数: #{item_num}", logger)
			
			driver.quit
			
			log_info_message("  => Driver再起動", logger)
			driver, wait = start_up_selenium()

			empty_row = 3

			i = 1

			create_results_csv("results")
			CSV.foreach("process/nike_items.csv", headers: true, encoding: 'SJIS:UTF-8') do |row|
				log_message = "=> #{i}/#{item_num}: データ取得中..."
				log_info_message(log_message, logger)

				# バリエーションURLを取得
				item_data = {
					item_url: row['item_url'],
					item_title: row['item_title'],
					item_img_url: row['item_img_url'],
					acquired_status: row['acquired_status'],
					item_vari_num_text: row['item_vari_num_text'],
					item_vari_img_ids: JSON.parse(row['item_vari_img_ids']),
				}

				variation_datas = retrieve_variation_url(driver, wait, item_data, logger)
				sleep rand(2..4)

				# バリエーションURLから商品データ取得
				variation_datas.each do |variation_data|
					item_datas = scrape_nike_page(driver, wait, variation_data[:variation_url], logger)
					if item_datas.empty?
						log_message = "==> NIKEデータ取得不可のため、次へ."
						log_info_message(log_message, logger)
						next
					end

					check_status = "TRUE" if variation_data[:must_check_status]
					data = [
						check_status,
						"=IMAGE(\"#{item_datas[:item_vari_img_url]}\")",
						row['item_title'].sjisable,
						item_datas[:item_code],
						item_datas[:item_url],
						item_datas[:item_price]
					]

					update_results_csv("results", data)
				end
				
				i += 1
			end

			# 前データのクリア
			log_message = "シートクリアを行います"
			log_info_message(log_message, logger)
			service = Google::Apis::SheetsV4::SheetsService.new
			service.authorization = authorize("settings/config.json")
			range = "#{sp_title}!A3" # 更新を開始するセル

			clear_sheet(service, sp_key, range)

			# リサーチ結果出力
			result_dat = []
			CSV.foreach("results/nike_datas.csv", encoding: "SJIS:UTF-8") do |row|
				data = [row[0], "FALSE", row[1], row[2], row[3], row[4], row[5]]
				result_dat << data
			end
			
			log_info_message(" -> シート更新中...", logger) 
			batch_update_sheet(service, sp_key, range, result_dat)
			log_info_message(" -> 更新完了", logger) 

			log_message = "------------------------------------------------------------"
			log_info_message(log_message, logger)
		rescue StandardError => e
      log_message = "エラーが発生しました: #{e.message}\n#{e.backtrace.join("\n")}"
      log_info_message(log_message, logger)
      next
    end
	end

	# ---------------------------------------------------
	# 稼働終了通知 
	# ---------------------------------------------------
	end_actual_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
	notion_notify.update_end_status(end_actual_time, "停止中")

rescue StandardError => e
  log_message = "リサーチ中にエラーが発生しました: #{e.message}\n#{e.backtrace.join("\n")}"
  log_info_message(log_message, logger)

	# 稼働終了通知（異常終了とエラー内容）
  end_actual_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")
  notion_notify.update_end_status_with_error(end_actual_time, "停止中", "エラーにより終了: #{e.message}")
ensure
  begin
    driver&.quit
  rescue StandardError => e
    log_message = "Driver終了時にエラーが発生しました: #{e.message}"
    log_info_message(log_message, logger)
  end
  
  log_message = "==================== 処理を終了します ===================="
  log_info_message(log_message, logger)
  exit 1
end

log_message = "==================== 更新処理完了 ツールを停止します ===================="
log_info_message(log_message, logger)
sleep(5)
