require "csv"
require 'fileutils'
require 'logger'
require "time"
require 'google_drive'

class String
  def sjisable
    str = self
    from_chr = "\u{301C 2212 00A2 00A3 00AC 2013 2014 2016 203E 00A0 00F8 203A}"
    to_chr   = "\u{FF5E FF0D FFE0 FFE1 FFE2 FF0D 2015 2225 FFE3 0020 03A6 3009}"
    str.tr!(from_chr, to_chr)
    str = str.encode("Windows-31J","UTF-8",:invalid => :replace,:undef=>:replace).encode("UTF-8","Windows-31J")
  end
end

def remove_old_logs_if_needed(logs_folder, max_logs)
  log_files = Dir.glob("#{logs_folder}/*.log")
  if log_files.size >= max_logs
    sorted_files = log_files.sort_by { |f| File.mtime(f) }
    File.delete(sorted_files.first)
  end
end

def move_files(source_folder, destination_folder, filename_pattern)
  FileUtils.mkdir_p(destination_folder)
  Dir.glob("#{source_folder}/*.csv").each do |file|
    if File.basename(file) =~ filename_pattern
      FileUtils.mv(file, "#{destination_folder}/#{File.basename(file)}")
    end
  end
end

def csv_to_hash(filename)
  begin
    # CSVファイルを開きます
    csv_data = CSV.read(filename, encoding: 'SJIS:UTF-8')

    # ハッシュを作成します
    hash_data = {}
    csv_data.each do |row|
      key = row[0] # A列の値
      value = row[1] # B列の値

      if key.nil? || value.nil?
        next
      end

      hash_data[key] = value
    end
    hash_data
  rescue => e
    {}
  end
end

def log_info_message(log_message, logger)
  puts log_message
  logger.info(log_message)
end

def log_error_message(log_message, logger)
  puts log_message
  logger.error(log_message)
end

def extract_numbers(str)
  str.scan(/\d+/).map(&:to_i)[0]
end

def create_process_csv(output_dir)
  CSV.open("#{output_dir}/nike_items.csv", "w", encoding: "SJIS:UTF-8") do |csv|
    header = ['item_url', 'item_title', 'item_img_url', 'acquired_status', 'item_vari_num_text', 'item_vari_img_ids']
    csv << header
  end
end

def update_process_csv(output_dir, data)
  CSV.open("#{output_dir}/nike_items.csv", "a", encoding: "SJIS:UTF-8") do |csv|
    csv << data
  end
end

def create_results_csv(output_dir)
  CSV.open("#{output_dir}/nike_datas.csv", "w", encoding: "SJIS:UTF-8") do |csv|
  end
end

def update_results_csv(output_dir, data)
  CSV.open("#{output_dir}/nike_datas.csv", "a", encoding: "SJIS:UTF-8") do |csv|
    csv << data
  end
end

def authorize(config_path)
  scope = 'https://www.googleapis.com/auth/spreadsheets'
  authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
    json_key_io: File.open(config_path),
    scope: scope
  )
  authorizer.fetch_access_token!
  authorizer
end

def clear_sheet(service, spreadsheet_id, range)
  sheet_name = range.split('!').first
  clear_range = "#{sheet_name}!A3:G"  # 3行目以降のA-G列をクリア
  
  request_body = Google::Apis::SheetsV4::ClearValuesRequest.new
  
  service.clear_values(spreadsheet_id, clear_range, request_body)
end

def batch_update_sheet(service, spreadsheet_id, range, values)
  value_range_object = Google::Apis::SheetsV4::ValueRange.new(values: values)
  
  request_body = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new(
    value_input_option: 'USER_ENTERED',
    data: [
      {
        range: range,
        values: values
      }
    ]
  )

  service.batch_update_values(spreadsheet_id, request_body)
end