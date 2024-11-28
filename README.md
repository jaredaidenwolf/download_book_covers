# Book Cover Downloader

A Ruby script that downloads book cover images from the Google Books API using ISBN numbers.

## Description

This script takes a CSV file containing ISBN numbers and attempts to download the highest quality book cover available for each ISBN from the Google Books API. It handles various scenarios including placeholder images, missing covers, and ISBNs not found in the Google Books database.

## Requirements

- Ruby 2.7 or higher
- No additional gems required (uses only standard library)

## Installation

1. Clone this repository or download the script:
```bash
git clone https://github.com/jaredaidenwolf/book-cover-downloader.git
```

2. Ensure you have Ruby installed:
```bash
ruby --version
```

## Usage

1. Prepare a CSV file with your ISBNs in the following format:
```csv
isbn
9780123456789
9780987654321
```

2. Run the script:
```bash
ruby download_covers.rb path/to/your/isbns.csv
```

## Output

The script creates:

1. A `book_covers` directory containing downloaded cover images
2. Three CSV files for tracking issues:
   - `no_cover_available_isbns.csv`: ISBNs where no cover was available
   - `placeholder_image_isbns.csv`: ISBNs where only placeholder images were found
   - `not_found_isbns.csv`: ISBNs not found in Google Books

### File Naming Convention

Downloaded covers are named using the pattern: `[sanitized_book_title]_[isbn].jpg`

## Features

- Downloads highest quality available cover images
- Detects and skips placeholder images
- Implements rate limiting to respect API constraints
- Provides detailed progress and error reporting
- Handles network errors with exponential backoff
- Creates comprehensive summary reports

## Limitations

- Uses the public Google Books API (no API key required, but has rate limits)
- Only downloads JPG format images
- Requires valid ISBN numbers in the input CSV

## Error Handling

The script includes:
- Network error retry logic with exponential backoff
- Placeholder image detection
- Invalid ISBN handling
- Rate limiting (0.5 seconds between requests)

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

[MIT License](LICENSE)

## Acknowledgments

- [Google Books API](https://developers.google.com/books) for providing book cover images
