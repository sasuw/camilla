<!-- ABOUT THE PROJECT -->
# About camilla

camilla is a standalone program for creating a [sitemap.xml](https://www.sitemaps.org/) file for static, internationalized websites. It runs as a single executable program on your Linux, Mac or Windows.

## Why?

There are many sitemap generators, but most of them are online or require specific dependencies (node, npm, Python). To fulfil my usage requirements I decided to create my own.

# Getting started as user

## Downloads

You can download the latest release from here: [https://github.com/sasuw/camilla/releases](https://github.com/sasuw/camilla/releases)

## Installing

Unpack the tar.gz or zip file and execute camilla from your terminal or command line window. For a more permanent installation, copy camilla e.g. to /usr/local/bin (Linux/MacOS) or to C:\Windows\system32 (Windows).

## Usage and functionality

Run camilla from the root directory of your static website. Camilla traverses through all directories, looking for files with type .html  and creates a sitemap.xml file in the root directory of your website. You have to specify at least the 

    --baseUrl

option (or -b for short), e.g.

    camilla -b 'https://example.com'

because all sitemap URLs have to be absolute. If you have an internationalized website, where every directory under the base url is a language directory, containing an identical file structure, you can run camilla with the

    -- baseDirContainsLanguageDirs

option (or -l for short). This creates alternate language references in the sitemap file (see [Tell Google about localized versions of your page](https://support.google.com/webmasters/answer/189077?hl=en)).

### Example of sitemap.xml produced by camilla

    <?xml version="1.0"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
      <url>
        <loc>https://example.com/de/index.html</loc>
        <lastmod>2020-09-13</lastmod>
        <xhtml:link  rel="alternate" hreflang="de" href="https://example.com/de/index.html"/>
        <xhtml:link  rel="alternate" hreflang="en" href="https://example.com/en/index.html"/>
        <xhtml:link  rel="alternate" hreflang="fi" href="https://example.com/fi/index.html"/>
      </url>
      <url>
        <loc>https://example.com/index.html</loc>
        <lastmod>2020-09-13</lastmod>
      </url>
      <url>
        <loc>https://example.com/en/index.html</loc>
        <lastmod>2020-09-13</lastmod>
        <xhtml:link  rel="alternate" hreflang="de" href="https://example.com/de/index.html"/>
        <xhtml:link  rel="alternate" hreflang="en" href="https://example.com/en/index.html"/>
        <xhtml:link  rel="alternate" hreflang="fi" href="https://example.com/fi/index.html"/>
      </url>
      <url>
        <loc>https://example.com/fi/index.html</loc>
        <lastmod>2020-09-13</lastmod>
        <xhtml:link  rel="alternate" hreflang="de" href="https://example.com/de/index.html"/>
        <xhtml:link  rel="alternate" hreflang="en" href="https://example.com/en/index.html"/>
        <xhtml:link  rel="alternate" hreflang="fi" href="https://example.com/fi/index.html"/>
      </url>
    </urlset>


# Getting started as developer

## Prerequisites

Dart is installed. See [https://dart.dev/get-dart](https://dart.dev/get-dart)

## Project structure

Standard dart project structure created with [pub](https://dart.dev/tools/pub/cmd), see [https://dart.dev/tools/pub/package-layout](https://dart.dev/tools/pub/package-layout)

The main executable, camilla.dart is located in the bin directory. The internal libraries used by camilla are in the lib directory.

The tests are in the test directory and the test data is in the test/data directory.

## Running the code

When you are in the project root directory, you can execute

    dart bin/camilla.dart

to run the program. For debugging, you can use e.g. [Visual Studio Code](https://code.visualstudio.com/).


# Miscellaneous

<!-- CONTRIBUTING -->
## Contributing

You can contribute to this project in many ways:

  * submitting an issue (bug or enhancement proposal) 
  * testing
  * contributing code

If you want to contribute code, please open an issue or contact me beforehand to ensure that your work in line with the project goals.

When you decide to commit some code:

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Built With

* [dart-xml](https://github.com/renggli/dart-xml)

<!-- LICENSE -->
## License

Distributed under the MIT License. See `LICENSE` for more information.