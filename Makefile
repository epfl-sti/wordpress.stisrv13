.DELETE_ON_ERROR:

.PHONY:all
all: news.json images redirect.csv

FROM_SCRAPER = newsatone-meta.json covershots-meta.json sti-website.gml
FROM_WORDPRESS = imported-permalinks.json

news.yaml news.json: prepare-news.pl $(FROM_SCRAPER)
	./prepare-news.pl

news-videos-only.yaml news-videos-only.json: prepare-news.pl $(FROM_SCRAPER)
	./prepare-news.pl --videos-only

images: prepare-images.pl covershots-meta.json
	./prepare-images.pl
	touch $@

redirect.csv: make-redirect-table.pl news.yaml $(FROM_WORDPRESS)
	./make-redirect-table.pl > $@
