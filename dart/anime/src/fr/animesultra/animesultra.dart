import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class AnimesUltra extends MProvider {
  AnimesUltra({required this.source});

  MSource source;

  final Client client = Client();

  @override
  String get baseUrl => source.baseUrl;

  String absUrl(String href) {
    if (href.startsWith("http")) return href;
    var clean = href;
    while (clean.startsWith("../")) {
      clean = clean.substring(3);
    }
    if (clean.startsWith("/")) clean = clean.substring(1);
    return "$baseUrl/$clean";
  }

  bool isAnimeLink(String href) {
    return RegExp(r"www1-sub/\d+-[^/]+/?$").hasMatch(href);
  }

  String animeUrlFromLink(String href) {
    final abs = absUrl(href);
    return abs.endsWith("/") ? abs.substring(0, abs.length - 1) : abs;
  }

  String nameFromAnimeUrl(String url) {
    final slug = url.split("/").last.replaceFirst(RegExp(r"^\d+-"), "");
    return slug.replaceAll("-", " ").trim();
  }

  List<MManga> parseListing(String res) {
    final doc = parseHtml(res);
    final items = doc.select("div.flw-item");
    List<MManga> animeList = [];
    for (var it in items) {
      final a = it.selectFirst("a.film-poster-ahref");
      final href = a?.getHref ?? "";
      final name = a?.attr("title") ?? "";
      if (href.isEmpty || !isAnimeLink(href)) continue;
      final img = it.selectFirst("img.film-poster-img")?.attr("data-src") ?? "";
      MManga anime = MManga();
      anime.name = name;
      anime.imageUrl = img.startsWith("http") ? img : "";
      anime.link = animeUrlFromLink(href);
      animeList.add(anime);
    }
    return animeList;
  }

  List<MManga> dedupe(List<MManga> list) {
    final seen = <String>{};
    List<MManga> result = [];
    for (var it in list) {
      if (it.link.isEmpty) continue;
      if (seen.add(it.link)) result.add(it);
    }
    return result;
  }

  Future<List<String>> sitemapUrls() async {
    final res = (await client.get(Uri.parse("$baseUrl/sitemap.xml"))).body;
    final matches = RegExp(r"<loc>([^<]+)</loc>").allMatches(res);
    List<String> urls = [];
    for (var m in matches) {
      final url = m.group(1) ?? "";
      if (RegExp(r"/www1-sub/\d+-[^/]+(/episode-\d+)?/?$").hasMatch(url)) {
        urls.add(url);
      }
    }
    return urls;
  }

  Future<List<String>> sitemapAnimeUrls() async {
    final urls = await sitemapUrls();
    return urls.where((u) => !u.contains("/episode-")).toList();
  }

  // ============================== Popular ===============================
  @override
  Future<MPages> getPopular(int page) async {
    final resSub = (await client.get(Uri.parse("$baseUrl/anime-vostfr/"))).body;
    final resDub = (await client.get(Uri.parse("$baseUrl/anime-vf/"))).body;
    List<MManga> animeList = dedupe([
      ...parseListing(resSub),
      ...parseListing(resDub),
    ]);
    final known = animeList.map((e) => e.link).toSet();
    try {
      final urls = await sitemapAnimeUrls();
      for (var url in urls) {
        final clean = animeUrlFromLink(url);
        if (known.contains(clean)) continue;
        MManga anime = MManga();
        anime.name = nameFromAnimeUrl(clean);
        anime.link = clean;
        animeList.add(anime);
      }
    } catch (_) {}
    return MPages(animeList, false);
  }

  // =============================== Latest ===============================
  @override
  Future<MPages> getLatestUpdates(int page) async {
    final resLatest =
        (await client.get(Uri.parse("$baseUrl/www1-sub/dernier-episodes/"))).body;
    final resSub = (await client.get(Uri.parse("$baseUrl/anime-vostfr/"))).body;
    final resDub = (await client.get(Uri.parse("$baseUrl/anime-vf/"))).body;
    List<MManga> animeList = dedupe([
      ...parseListing(resLatest),
      ...parseListing(resSub),
      ...parseListing(resDub),
    ]);
    return MPages(animeList, false);
  }

  // =============================== Search ===============================
  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final queryTrimmed = query.trim();
    if (queryTrimmed.startsWith("https://")) {
      MManga anime = MManga();
      anime.name = nameFromAnimeUrl(queryTrimmed);
      anime.link = queryTrimmed.endsWith("/")
          ? queryTrimmed.substring(0, queryTrimmed.length - 1)
          : queryTrimmed;
      return MPages([anime], false);
    }

    final urls = await sitemapAnimeUrls();
    final tokens = queryTrimmed
        .toLowerCase()
        .split(RegExp(r"\s+"))
        .where((t) => t.isNotEmpty)
        .toList();
    List<MManga> animeList = [];
    final seen = <String>{};
    for (var url in urls) {
      final clean = animeUrlFromLink(url);
      if (!seen.add(clean)) continue;
      final slug = clean.split("/").last.toLowerCase();
      var match = true;
      for (var token in tokens) {
        if (!slug.contains(token)) {
          match = false;
          break;
        }
      }
      if (!match) continue;
      MManga anime = MManga();
      anime.name = nameFromAnimeUrl(clean);
      anime.link = clean;
      animeList.add(anime);
    }
    return MPages(animeList, false);
  }

  // =============================== Detail ===============================
  @override
  Future<MManga> getDetail(String url) async {
    final statusList = [
      {"En cours": 0, "Terminé": 1},
    ];

    final animeUrl = url.endsWith("/") ? url.substring(0, url.length - 1) : url;
    final res = (await client.get(Uri.parse(animeUrl))).body;
    final doc = parseHtml(res);
    var anime = MManga();
    anime.name = doc.selectFirst("h1.film-name")?.text ?? "";
    anime.description = doc.selectFirst("div.film-description .text")?.text ?? "";
    final img = doc.selectFirst("div.anisc-poster img")?.attr("src") ?? "";
    anime.imageUrl = img.startsWith("http") ? img : "";
    final status = doc
            .xpathFirst(
              '//*[contains(@class,"item item-title") and contains(.,"Status:")]/span[@class="name"]/text()',
            )
            ?.trim() ??
        "";
    if (status.isNotEmpty) anime.status = parseStatus(status, statusList);
    anime.genre = xpath(
      res,
      '//*[contains(@class,"item item-list") and contains(.,"Genres:")]/a/text()',
    );

    List<MChapter>? episodesList = [];
    final prefix = animeUrl.split("/").last;
    final episodeUrls = <String>[];
    try {
      final urls = await sitemapUrls();
      for (var u in urls) {
        if (u.contains("/episode-") && u.contains("/$prefix/")) {
          episodeUrls.add(animeUrlFromLink(u));
        }
      }
    } catch (_) {}
    if (episodeUrls.isEmpty) {
      final watch = doc.selectFirst("a.btn-play")?.getHref ?? "";
      if (watch.isNotEmpty && watch.contains("/episode-")) {
        episodeUrls.add(animeUrlFromLink(watch));
      }
    }
    episodeUrls.sort((a, b) {
      final na = int.tryParse(
            a.split("/episode-").last.replaceAll("/", ""),
          ) ??
          0;
      final nb = int.tryParse(
            b.split("/episode-").last.replaceAll("/", ""),
          ) ??
          0;
      return nb.compareTo(na);
    });
    for (var epUrl in episodeUrls) {
      final num = epUrl.split("/episode-").last.replaceAll("/", "");
      var episode = MChapter();
      episode.name = "Episode $num";
      episode.url = epUrl;
      episodesList.add(episode);
    }
    anime.chapters = episodesList;
    return anime;
  }

  // =============================== Videos ===============================
  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = (await client.get(Uri.parse(url))).body;
    final doc = parseHtml(res);
    final servers = doc.select("div.server-item");
    List<MVideo> videos = [];
    for (var server in servers) {
      final name = server.text.trim();
      final embed = server.attr("data-embed");
      if (embed.isEmpty || !embed.startsWith("http")) continue;
      final host = Uri.parse(embed).host;
      List<MVideo> extracted = [];
      try {
        if (host.contains("filemoon")) {
          extracted = await filemoonExtractor(embed, name, "");
        } else if (host.contains("sendvid")) {
          extracted = await sendVidExtractor(embed, null, name);
        } else if (host.contains("sibnet")) {
          extracted = await sibnetExtractor(embed, name);
        } else if (host.contains("mp4upload")) {
          extracted = await mp4UploadExtractor(embed, null, name, "");
        } else if (host.contains("dood")) {
          extracted = await doodExtractor(embed, name);
        } else if (host.contains("streamtape")) {
          extracted = await streamTapeExtractor(embed, name);
        } else if (host.contains("voe")) {
          extracted = await voeExtractor(embed, name);
        } else {
          extracted = await streamWishExtractor(embed, name);
        }
      } catch (_) {}
      videos.addAll(extracted);
    }
    return videos;
  }
}

AnimesUltra main(MSource source) {
  return AnimesUltra(source: source);
}
