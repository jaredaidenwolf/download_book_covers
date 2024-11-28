require "csv"
require "digest"
require "fileutils"
require "json"
require "net/http"

# Downloads book covers from Google Books API using ISBN numbers
#
# @example
#   downloader = BookCoverDownloader.new("books.csv")
#   downloader.process
#
class BookCoverDownloader
  # Base URL for Google Books API
  GOOGLE_BOOKS_API_URL = "https://www.googleapis.com/books/v1/volumes"

  # Directory where book covers will be saved
  OUTPUT_DIR = "book_covers"

  # Known MD5 hashes of placeholder images from Google Books
  KNOWN_PLACEHOLDER_HASHES = [
    "a64fa89d7ebc97075c1d363fc5fea71f",
    "1fe98bd081e1f98c8193d52c74cf2ad2"
  ].freeze

  # Initialize a new BookCoverDownloader
  #
  # @param csv_path [String] path to CSV file containing ISBNs
  # @return [BookCoverDownloader] new instance
  def initialize(csv_path)
    @csv_path = csv_path
    @no_cover_isbns = []
    @placeholder_isbns = []
    @not_found_isbns = []
    @retry_delay = 1
    setup_output_directory
  end

  # Process all ISBNs in the CSV file
  #
  # @return [void]
  def process
    @total_books = CSV.read(@csv_path).count - 1
    @current_book = 0

    CSV.foreach(@csv_path, headers: true) do |row|
      @current_book += 1
      process_isbn(row["isbn"].strip, @current_book, @total_books)
    end

    write_failed_downloads if @no_cover_isbns.any? || @placeholder_isbns.any? || @not_found_isbns.any?
  end

  private

  # Create output directory if it doesn't exist
  #
  # @return [void]
  def setup_output_directory
    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  # Process a single ISBN
  #
  # @param isbn [String] the ISBN to process
  # @param current_book [Integer] current book number
  # @param total_books [Integer] total number of books
  # @return [void]
  def process_isbn(isbn, current_book, total_books)
    puts "\nProcessing ISBN: #{isbn} (#{current_book}/#{total_books})"
    puts "Status: Starting process"
    retry_count = 0
    max_retries = 4 # Will result in delays of 1, 2, 4, 8, 16 seconds

    begin
      if result = fetch_book_cover(isbn)
        save_cover(*result)
        @retry_delay = 1
      else
        record_failure(isbn)
      end

      sleep(0.5) # Rate limiting
    rescue => e
      handle_error(isbn, e, retry_count, max_retries)
    end
  end

  # Fetch book cover from Google Books API
  #
  # @param isbn [String] ISBN to fetch cover for
  # @return [Array<String, String, String>, nil] array containing [image_url, filename, image_data] or nil if no cover found
  def fetch_book_cover(isbn)
    puts "Status: Fetching book data"
    response = fetch_google_books_data(isbn)
    puts "Status: API response received"
    puts "Items found: #{response["items"]&.count || 0}"

    unless response["items"]
      @not_found_isbns << isbn
      return nil
    end

    found_placeholder = false

    response["items"].each do |item|
      volume_info = item["volumeInfo"]
      image_url = extract_image_url(volume_info)
      next unless image_url

      image_data = download_image(image_url)
      if placeholder_image?(image_data)
        found_placeholder = true
        next
      end

      filename = generate_filename(isbn, volume_info["title"])
      return [image_url, filename, image_data]
    end

    if found_placeholder
      @placeholder_isbns << isbn
    else
      @no_cover_isbns << isbn
    end
    nil
  end

  # Fetch book data from Google Books API
  #
  # @param isbn [String] ISBN to search for
  # @return [Hash] parsed JSON response from API
  def fetch_google_books_data(isbn)
    query = URI.encode_www_form(q: "isbn:#{isbn}")
    uri = URI("#{GOOGLE_BOOKS_API_URL}?#{query}")
    JSON.parse(Net::HTTP.get(uri))
  end

  # Extract highest quality image URL from volume info
  #
  # @param volume_info [Hash] volume info from API response
  # @return [String, nil] image URL or nil if no image available
  def extract_image_url(volume_info)
    return nil unless volume_info["imageLinks"]

    image_url = volume_info["imageLinks"]["extraLarge"] ||
                volume_info["imageLinks"]["large"] ||
                volume_info["imageLinks"]["medium"] ||
                volume_info["imageLinks"]["small"] ||
                volume_info["imageLinks"]["thumbnail"]

    return nil unless image_url

    # Find and replace common URL modifiers
    image_url.gsub!("http:", "https:")
    image_url.gsub!(/zoom=\d/, "zoom=3")
    image_url.gsub!("edge=curl", "edge=none")
    image_url.gsub!(/&pg=PP\d+/, "")
    image_url
  end

  # Download image data from URL
  #
  # @param url [String] URL to download from
  # @return [String] binary image data
  def download_image(url)
    Net::HTTP.get(URI(url))
  end

  # Check if image is a placeholder
  #
  # @param image_data [String] binary image data
  # @return [Boolean] true if image is a placeholder
  def placeholder_image?(image_data)
    hash = Digest::MD5.hexdigest(image_data)
    puts "Image hash: #{hash}"

    if KNOWN_PLACEHOLDER_HASHES.include?(hash)
      puts "Detected placeholder image with hash: #{hash}"
      true
    else
      false
    end
  end

  # Generate filename for book cover
  #
  # @param isbn [String] book ISBN
  # @param title [String] book title
  # @return [String] sanitized filename
  def generate_filename(isbn, title)
    sanitized_title = title.gsub(/[^0-9A-Za-z\-]/, '_').downcase
    "#{sanitized_title}_#{isbn}.jpg"
  end

  # Save cover image to file
  #
  # @param image_url [String] source URL
  # @param filename [String] destination filename
  # @param image_data [String] binary image data
  # @return [void]
  def save_cover(image_url, filename, image_data)
    File.open(File.join(OUTPUT_DIR, filename), "wb") do |file|
      file.write(image_data)
    end
    puts "Successfully downloaded cover for ISBN: #{filename}"
  end

  # Record failure to download cover
  #
  # @param isbn [String] ISBN that failed
  # @return [void]
  def record_failure(isbn)
    puts "No cover found for ISBN: #{isbn}"
  end

  # Write summary and failed downloads to files
  #
  # @return [void]
  def write_failed_downloads
    write_summary
    write_failed_csvs
  end

  # Write summary statistics
  #
  # @return [void]
  def write_summary
    successful_count = Dir[File.join(OUTPUT_DIR, "*.jpg")].count
    placeholder_count = @placeholder_isbns.count
    no_cover_count = @no_cover_isbns.count
    not_found_count = @not_found_isbns.count
    total_processed = successful_count + placeholder_count + no_cover_count + not_found_count

    puts "\nSummary:"
    puts "Total ISBNs: #{@total_books}"
    puts "Successfully downloaded: #{successful_count}"
    puts "Placeholder images: #{placeholder_count}"
    puts "No covers available: #{no_cover_count}"
    puts "ISBNs not found in Google Books: #{not_found_count}"
    puts "Total processed: #{total_processed}"
    puts "Unaccounted for: #{@total_books - total_processed}"
  end

  # Write failed downloads to CSV files
  #
  # @return [void]
  def write_failed_csvs
    write_csv("no_cover_available_isbns.csv", @no_cover_isbns) if @no_cover_isbns.any?
    write_csv("placeholder_image_isbns.csv", @placeholder_isbns) if @placeholder_isbns.any?
    write_csv("not_found_isbns.csv", @not_found_isbns) if @not_found_isbns.any?
  end

  # Write ISBNs to CSV file
  #
  # @param filename [String] output filename
  # @param isbns [Array<String>] list of ISBNs to write
  # @return [void]
  def write_csv(filename, isbns)
    CSV.open(filename, "w") do |csv|
      csv << ["isbn"]
      isbns.each { |isbn| csv << [isbn] }
    end
    puts "\nISBNs have been written to #{filename}"
  end
end

# Main execution
if ARGV.empty?
  puts "Please provide the path to the CSV file"
  puts "Usage: ruby download_covers.rb path/to/isbn_list.csv"
  exit 1
end

downloader = BookCoverDownloader.new(ARGV[0])
downloader.process
