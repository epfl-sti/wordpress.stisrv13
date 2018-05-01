.DELETE_ON_ERROR:

.PHONY:all
all: news.json images redirect.csv

FROM_SCRAPER = newsatone-meta.json covershots-meta.json sti-website.gml
FROM_WORDPRESS = imported-permalinks.json
PERL_DEPS    = STISRV13.pm $(wildcard STISRV13/%.pm)
news.yaml news.json: prepare-news.pl $(FROM_SCRAPER) $(PERL_DEPS)
	./prepare-news.pl

news-videos-only.yaml news-videos-only.json: prepare-news.pl $(FROM_SCRAPER) $(PERL_DEPS)
	./prepare-news.pl --videos-only

images stock-images.json: prepare-images.pl covershots-meta.json $(PERL_DEPS)
	./prepare-images.pl
	touch $@

redirect.csv: make-redirect-table.pl news.yaml $(FROM_WORDPRESS)
	./make-redirect-table.pl > $@
