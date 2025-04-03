#!/bin/bash

# Create base directory for test structure
BASE_DIR="camilla_test"
mkdir -p "$BASE_DIR"

# Function to create an HTML file with basic content
create_html_file() {
    local filepath="$1"
    local title="$2"
    cat > "$filepath" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${title}</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>${title}</h1>
    <p>This is a test page for Camilla sitemap generator.</p>
</body>
</html>
EOF
}

# Create main directory structure
mkdir -p "$BASE_DIR/blog"
mkdir -p "$BASE_DIR/products"
mkdir -p "$BASE_DIR/about"
mkdir -p "$BASE_DIR/news/2023"
mkdir -p "$BASE_DIR/news/2022"

# Create HTML files in root directory
create_html_file "$BASE_DIR/index.html" "Home Page"
create_html_file "$BASE_DIR/about.html" "About Us"
create_html_file "$BASE_DIR/contact.html" "Contact Us"

# Create blog posts
create_html_file "$BASE_DIR/blog/post1.html" "First Blog Post"
create_html_file "$BASE_DIR/blog/post2.html" "Second Blog Post"
create_html_file "$BASE_DIR/blog/index.html" "Blog Index"

# Create product pages
create_html_file "$BASE_DIR/products/product1.html" "Product One"
create_html_file "$BASE_DIR/products/product2.html" "Product Two"
create_html_file "$BASE_DIR/products/index.html" "Products Catalog"

# Create about section
create_html_file "$BASE_DIR/about/team.html" "Our Team"
create_html_file "$BASE_DIR/about/mission.html" "Our Mission"
create_html_file "$BASE_DIR/about/index.html" "About Section"

# Create news articles
create_html_file "$BASE_DIR/news/2023/article1.html" "News 2023 - Article 1"
create_html_file "$BASE_DIR/news/2023/article2.html" "News 2023 - Article 2"
create_html_file "$BASE_DIR/news/2022/article1.html" "News 2022 - Article 1"
create_html_file "$BASE_DIR/news/index.html" "News Archive"

# Create some non-HTML files to test exclusion
touch "$BASE_DIR/style.css"
touch "$BASE_DIR/script.js"
touch "$BASE_DIR/.htaccess"
touch "$BASE_DIR/robots.txt"

# Create a README file with usage instructions
cat > "$BASE_DIR/README.txt" << EOF
Test Directory Structure for Camilla Sitemap Generator

This directory structure contains various HTML files and directories
to test the Camilla sitemap generator functionality.

Directory structure:
- /blog/         : Blog posts and index
- /products/     : Product pages
- /about/        : About section
- /news/         : News articles by year
- Various root level pages and files

To use with Camilla:
1. Navigate to this directory
2. Run Camilla with appropriate parameters
3. Check the generated sitemap.xml
EOF

echo "Test directory structure created in '$BASE_DIR'"
echo "Total HTML files created: $(find "$BASE_DIR" -name "*.html" | wc -l)"
echo "See $BASE_DIR/README.txt for more information"