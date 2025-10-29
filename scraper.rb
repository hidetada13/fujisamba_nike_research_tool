require "selenium-webdriver"
require 'json'

def start_up_selenium
  options = Selenium::WebDriver::Chrome::Options.new
  # options.add_argument('--headless')
  client = Selenium::WebDriver::Remote::Http::Default.new
  driver = Selenium::WebDriver.for :chrome, options: options, :http_client => client
  driver.manage.window.resize_to(1920, 1280)
  wait = Selenium::WebDriver::Wait.new(timeout: 15)
  return driver, wait
end

def scrape_nike_list_page(driver, wait, url, logger)
  # XPATH ##############################################
  wall_header_xpath = "//div[@class='wall-header__content']"
  item_card_xpath = "//div[@class='product-card__body']"
  item_url_xpath = "./figure/a"
  item_icon_img_xpath = "./figure/a[2]/div[1]/img[1]"
  item_title_xpath = "./figure/div[1]//div[@class='product-card__title']"
  item_vari_num_xpath = "./figure/div[1]/div[2]"
  item_vari_img_xpath = "./figure//div[@class='product-card__colorways-thumbs']/a/div/picture/img[1]"
  ######################################################
  log_message = "URL: #{url}"
  logger.info(log_message)

  driver.get(url)
  wait.until { driver.find_element(:xpath, wall_header_xpath).displayed? }

  # スクロールしながら全商品を取得
  previous_items_count = 0

  while true
    # 現在の高さを10分割してスクロール
    total_height = driver.execute_script("return document.body.scrollHeight")
    scroll_step = total_height / 10
    current_position = 0

    # 10段階でスクロール
    10.times do
      current_position += scroll_step
      scroll_script = "window.scrollTo({ top: #{current_position}, behavior: 'smooth' });"
      driver.execute_script(scroll_script)
      sleep rand(0.3..0.7)
    end
    sleep(rand(3..5))

    # 現在の商品数を取得
    current_items = driver.find_elements(:xpath, item_card_xpath)
    current_items_count = current_items.size
    log_info_message("取得数: #{current_items.size}", logger)

    # 商品数に変化がなければ終了
    break if current_items_count == previous_items_count
    
    previous_items_count = current_items_count
  end

  # 商品カード要素をすべて取得
  item_datas = []
  item_card_elements = driver.find_elements(:xpath, item_card_xpath)

  log_info_message("全取得数: #{item_card_elements.size}", logger)
  # 各商品要素からデータ抽出
  item_card_elements.each_with_index do |item_card_element, num|
    begin
      log_message = "Nike Item: #{num + 1}"
      logger.info(log_message)

      item_url = item_card_element.find_element(:xpath, item_url_xpath).attribute("href")
      item_title = item_card_element.find_element(:xpath, item_title_xpath).text
      item_vari_num_text = item_card_element.find_element(:xpath, item_vari_num_xpath).text
      item_vari_num = extract_numbers(item_vari_num_text)

      if item_vari_num > 4
        acquired_status = false
      else
        acquired_status = true
      end
      
      # 対象商品要素までスクロール後、マウスホバー
      item_icon_img_element = item_card_element.find_element(:xpath, item_icon_img_xpath)
      driver.execute_script("arguments[0].scrollIntoView(true);", item_icon_img_element)
      actions = driver.action
      actions.move_to(item_icon_img_element).perform
      sleep(1)

      if item_vari_num == 1
        item_vari_img_ids = [
          item_icon_img_element.attribute("src").split("/")[-2]
        ]
      else
        item_vari_img_elements = item_card_element.find_elements(:xpath, item_vari_img_xpath)
        item_vari_img_ids = item_vari_img_elements.map { |element| element.attribute("src").split("/")[-2] }
      end
      
      item_data = {
        item_url: item_url,
        item_title: item_title,
        item_img_url: item_icon_img_element.attribute("src"),
        acquired_status: acquired_status,
        item_vari_num_text: item_vari_num_text,
        item_vari_img_ids: item_vari_img_ids
      }

      log_message = "==> 取得完: #{item_data}"
      log_info_message(log_message, logger)
      item_datas.push(item_data)
    rescue => e
      log_message = "==> エラーが発生しました. 商品データが取得できません: #{e.message}"
      log_error_message(log_message, logger)
      next
    end
  end
  
  return item_datas
rescue StandardError => e
  log_message = "==> エラーが発生しました. NIKE商品URLが取得できません: #{e.message}"
  log_error_message(log_message, logger)
  return [] # エラー時は空の配列を返す
end

def retrieve_variation_url(driver, wait, item_data ,logger)
  # XPATH ##############################################
  # variations_xpath = "//div[@class='colorway-images-wrapper']/fieldset/div"
  variations_xpath = "//div[@id='colorway-picker-container']/a"
  variation_item_code_xpath = "./div/input"
  variation_img_xpath = ".//img" # 在庫なしの場合はaタグ直下ではないため
  # variation_img_xpath = "./img"
  ######################################################
  # バリエーションURL生成のためのベースURL
  base_url = item_data[:item_url][0...item_data[:item_url].rindex('/')+1]
  
  # 商品URLにアクセスしてバリエーションURLを生成
  driver.get(item_data[:item_url])
  # wait.until { driver.find_element(:xpath, variations_xpath).displayed? }
  variations = driver.find_elements(:xpath, variations_xpath)
  
  if variations.size == 0
    log_message = "==> 取得完. 1バリエーションのみ"
    log_info_message(log_message, logger)

    variation_datas = [
      {
        variation_url: item_data[:item_url],
        must_check_status: false
      }
    ]
    return variation_datas
  end
  
  variation_datas = []
  variations.each do |variation|
    if item_data[:acquired_status] == true
      img_id = variation.find_element(:xpath, variation_img_xpath).attribute("src").split("/")[-2]
      if item_data[:item_vari_img_ids].include?(img_id)
        # item_code = variation.find_element(:xpath, variation_item_code_xpath).attribute("value")
        item_code = variation.find_element(:xpath, variation_img_xpath).attribute("id").gsub("colorway-chip-", "")
        
        variation_data = {
          variation_url: base_url + item_code,
          must_check_status: false,
        }
        variation_datas.push(variation_data)
      end
    else
      must_check_status = true
      img_id = variation.find_element(:xpath, variation_img_xpath).attribute("src").split("/")[-2]
      if item_data[:item_vari_img_ids].include?(img_id)
        must_check_status = false
      end
      # item_code = variation.find_element(:xpath, variation_item_code_xpath).attribute("value")
      item_code = variation.find_element(:xpath, variation_img_xpath).attribute("id").gsub("colorway-chip-", "")
      
      variation_data = {
        variation_url: base_url + item_code,
        must_check_status: must_check_status,
      }
      variation_datas.push(variation_data)
    end
  end

  log_message = "==> 取得完: #{variation_datas.size}バリエーション"
  log_info_message(log_message, logger)

  return variation_datas

# rescue TimeoutError => e
#   log_message = "==> TimeoutErrorが発生. 1バリエーションのみ: #{e.message}"
#   log_error_message(log_message, logger)
#   variation_datas = [
#     {
#       variation_url: item_data[:item_url],
#       must_check_status: false
#     }
#   ]
# rescue StandardError => e
#   log_message = "==> 一般エラーが発生しました. 1バリエーションのみ: #{e.message}"
#   log_error_message(log_message, logger)
#   variation_datas = [
#     {
#       variation_url: item_data[:item_url],
#       must_check_status: false
#     }
#   ]
rescue => e
  log_message = "==> エラーが発生しました. 1バリエーションのみ: #{e.message}"
  log_error_message(log_message, logger)
  variation_datas = [
    {
      variation_url: item_data[:item_url],
      must_check_status: false
    }
  ]
end

def scrape_nike_page(driver, wait, url, logger)
  # XPATH ##############################################
  item_vari_img_xpath = "//*[@data-testid='ThumbnailListContainer']/div/label/img"
  item_price_xpath = "//*[@id='price-container']/span"
  item_price_text_xpath = "//div[@data-testid='additional-price-message-jp']/div[2]"
  ######################################################
  
  # URLが表示中でない場合にアクセス
  current_url = driver.current_url
  if current_url != url
    driver.get(url)
    wait.until { driver.find_element(:xpath, item_price_xpath).displayed? }
  end

  # トップ画像取得
  item_vari_img_element = driver.find_element(:xpath, item_vari_img_xpath)
  item_vari_img_url = item_vari_img_element.attribute("src")
  
  # 型番取得
  item_code = url[url.rindex('/') + 1..-1]
  
  # 価格取得
  price_text = driver.find_element(:xpath, item_price_xpath).text
  price = extract_and_sum_price(price_text)
  
  # セール判別
  begin
    price_sale_text = driver.find_element(:xpath, item_price_text_xpath).text
    if price_sale_text.include?("セール価格")
      sale_item = true
    else
      sale_item = false
    end
  rescue => e
    sale_item = false
  end
  
  item_datas = {
    item_code: item_code,
    item_url: url,
    item_vari_img_url: item_vari_img_url,
    item_price: price,
    sale_item: sale_item
  }

  log_message = "==> NIKEデータ取得OK: #{item_datas}"
  logger.info(log_message)
  return item_datas
rescue => e
  log_message = "==> NIKEデータ取得NG:ERROR!#{e}"
  log_error_message(log_message, logger)
  item_datas = {}
end

def extract_and_sum_price(input_str)
  # "+"が含まれる場合は、商品価格と送料を分割して合算
  if input_str.include?('＋')
    # "+"の前の数値（商品価格）を抽出
    product_price = input_str.split('＋').first.gsub(/[円,]/, '').to_i
    # "+"の後の数値（送料）を抽出
    shipping_price = input_str.split('＋').last.match(/(\d+)/)[0].to_i
    # 商品価格と送料を合算
    # total_price = product_price + shipping_price
    total_price = product_price
  else
    # "+"が含まれない場合、"￥"または"円"に続く数値を抽出して価格として使用
    total_price = input_str.gsub(/[^0-9]/, '').to_i
  end

  total_price
end