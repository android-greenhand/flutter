import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer' as dev;
import '../models/unified_article.dart';

/// 统一的文章服务类，带缓存支持
class UnifiedArticleService {
  static const String owner = 'android-greenhand';
  static const String repo = 'Logseq';
  static const String contentsPath = 'pages/contents.md';
  static const String _baseUrl = 'https://ktor-vercel.vercel.app';
  static const Map<String, String> _headers = {'Accept': 'application/json'};

  // ============ 缓存 ============
  static List<UnifiedArticle>? _articlesCache;
  static Set<String>? _existingFilesCache;
  static String? _contentsCache;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 10);

  /// 清除所有缓存
  static void clearCache() {
    _articlesCache = null;
    _existingFilesCache = null;
    _contentsCache = null;
    _cacheTime = null;
  }

  static bool get _isCacheValid {
    if (_cacheTime == null || _articlesCache == null) return false;
    return DateTime.now().difference(_cacheTime!) < _cacheDuration;
  }

  // ============ 公共 API ============

  /// 获取所有分类文章（平铺列表，带缓存）
  static Future<List<UnifiedArticle>> getAllCategorizedArticles({
    bool validateFiles = true,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isCacheValid) {
      return List.from(_articlesCache!);
    }

    try {
      // 获取 contents.md
      final contents = await _getContentsMarkdown(forceRefresh: forceRefresh);

      // 如果需要验证文件，获取文件列表
      Set<String>? existingFiles;
      if (validateFiles) {
        existingFiles = await _getExistingFiles(forceRefresh: forceRefresh);
      }

      final categoriesMap = _parseCategories(contents);

      final List<UnifiedArticle> result = [];
      for (final entry in categoriesMap.entries) {
        for (final title in entry.value) {
          final cleanTitle = title.trim();
          if (validateFiles && existingFiles != null && !existingFiles.contains(cleanTitle)) {
            continue;
          }
          result.add(_createArticle(cleanTitle, entry.key));
        }
      }

      _articlesCache = result;
      _cacheTime = DateTime.now();
      return List.from(result);
    } catch (e) {
      dev.log('获取所有分类文章失败', name: 'UnifiedArticleService', error: e);
      rethrow;
    }
  }

  /// 获取分类文章列表（按分类分组，带缓存）
  static Future<List<ArticleCategory>> getCategorizedArticles({
    bool validateFiles = true,
    bool forceRefresh = false,
  }) async {
    final articles = await getAllCategorizedArticles(
      validateFiles: validateFiles,
      forceRefresh: forceRefresh,
    );

    final Map<String, List<UnifiedArticle>> grouped = {};
    for (final article in articles) {
      grouped.putIfAbsent(article.category, () => []).add(article);
    }

    return grouped.entries
        .map((e) => ArticleCategory(name: e.key, articles: e.value))
        .toList();
  }

  /// 获取文章详情（内容、摘要、commit信息）
  static Future<UnifiedArticle> getArticleDetails(UnifiedArticle article) async {
    // 如果已经有详情，直接返回
    if (article.content.isNotEmpty) return article;

    try {
      // 并行请求内容和 commit 信息
      final results = await Future.wait([
        getMarkdownContent(owner, repo, article.path),
        getFileCommitInfo(owner, repo, article.path),
      ]);

      final content = results[0] as String;
      final commitInfo = results[1] as Map<String, dynamic>?;

      if (content.isEmpty) return article;

      final rawImageUrl = _extractImageFromContent(content);
      final excerpt = _extractExcerpt(content);

      // 转换图片URL为完整的下载链接
      String? imageUrl;
      if (rawImageUrl != null && rawImageUrl.isNotEmpty) {
        imageUrl = await _resolveImageUrl(rawImageUrl, article.path);
      }

      final updatedArticle = UnifiedArticle(
        name: article.name,
        title: article.title,
        path: article.path,
        downloadUrl: article.downloadUrl,
        sha: article.sha,
        size: article.size,
        type: article.type,
        // 使用真实的 commit 时间
        commitDate: commitInfo?['date'] ?? '',
        publishDate: commitInfo?['date'] != null
            ? DateTime.tryParse(commitInfo!['date'])
            : null,
        imageUrl: imageUrl ?? article.imageUrl,
        category: article.category,
        categories: article.categories,
        description: excerpt,
        excerpt: excerpt,
        content: content,
        author: commitInfo?['author'] ?? '',
        date: article.date,
        slug: article.slug,
        tags: article.tags,
      );

      // 更新缓存中的文章
      _updateCachedArticle(updatedArticle);
      return updatedArticle;
    } catch (e) {
      dev.log('获取文章详情失败', name: 'UnifiedArticleService', error: e);
      return article;
    }
  }

  /// 获取文章内容
  static Future<String> getMarkdownContent(String owner, String repo, String path) async {
    try {
      final apiUrl = Uri.parse('$_baseUrl/api/contents/$path?owner=$owner&repo=$repo');
      final response = await http.get(apiUrl, headers: _headers);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (!data.containsKey('content')) {
          throw Exception('响应中缺少文件内容');
        }
        final rawContent = data['content'] as String;
        final cleanBase64 = rawContent.replaceAll(RegExp(r'[\n\r ]'), '');
        return utf8.decode(base64.decode(cleanBase64));
      }
      throw Exception('获取文件内容失败: ${response.statusCode}');
    } catch (e) {
      throw Exception('加载内容错误: $e');
    }
  }

  /// 获取图片下载链接
  static Future<String> getImageContent(String fileName) async {
    final url = Uri.parse('$_baseUrl/api/contents/$fileName?owner=$owner&repo=$repo');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      return data['download_url'];
    }
    throw Exception('Failed to load image: ${response.statusCode}');
  }

  /// 获取文件 commit 信息
  static Future<Map<String, dynamic>?> getFileCommitInfo(String owner, String repo, String path) async {
    try {
      final url = Uri.parse('$_baseUrl/api/commits/$path?owner=$owner&repo=$repo');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final List<dynamic> commits = json.decode(response.body);
        if (commits.isNotEmpty) {
          final commit = commits[0];
          return {
            'date': commit['commit']['author']['date'],
            'message': commit['commit']['message'],
            'author': commit['commit']['author']['name'],
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============ 私有方法 ============

  static Future<String> _getContentsMarkdown({bool forceRefresh = false}) async {
    if (!forceRefresh && _contentsCache != null) {
      return _contentsCache!;
    }
    _contentsCache = await getMarkdownContent(owner, repo, contentsPath);
    return _contentsCache!;
  }

  static Future<Set<String>> _getExistingFiles({bool forceRefresh = false}) async {
    if (!forceRefresh && _existingFilesCache != null) {
      return _existingFilesCache!;
    }

    try {
      final url = Uri.parse('$_baseUrl/api/contents/pages?owner=$owner&repo=$repo');
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final List<dynamic> items = json.decode(response.body);
        _existingFilesCache = items
            .where((item) => item['type'] == 'file' && item['name'].toString().endsWith('.md'))
            .map((item) => item['name'].toString().replaceAll('.md', ''))
            .toSet();
        return _existingFilesCache!;
      }
      return {};
    } catch (e) {
      dev.log('获取 pages 目录异常', name: 'UnifiedArticleService', error: e);
      return {};
    }
  }

  static UnifiedArticle _createArticle(String title, String categoryName) {
    final path = 'pages/$title.md';
    return UnifiedArticle(
      name: title,
      title: title,
      path: path,
      downloadUrl: path,
      // 不设置假时间，留空表示未加载
      commitDate: '',
      imageUrl: 'https://picsum.photos/800/400',
      category: categoryName,
      categories: [categoryName],
      slug: path.replaceAll('.md', '').replaceAll('/', '-'),
    );
  }

  static void _updateCachedArticle(UnifiedArticle article) {
    if (_articlesCache == null) return;
    final index = _articlesCache!.indexWhere((a) => a.path == article.path);
    if (index != -1) {
      _articlesCache![index] = article;
    }
  }

  static Map<String, List<String>> _parseCategories(String markdown) {
    final Map<String, List<String>> categories = {};
    String currentCategory = '';
    int currentIndentLevel = 0;
    bool insideMillions = false;
    int millionsIndent = -1;

    for (var line in markdown.split('\n')) {
      int indentLevel = line.length - line.trimLeft().length;
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.contains('**^^Millions of knowledge^^**')) {
        insideMillions = true;
        millionsIndent = indentLevel;
        continue;
      }

      if (insideMillions && indentLevel <= millionsIndent && line.startsWith('-')) {
        if (!line.startsWith('- [[') || line.contains('个人')) break;
      }

      if (!insideMillions) continue;
      if (line.contains('collapsed::')) continue;

      if (indentLevel == millionsIndent + 1 && line.startsWith('- [[')) {
        final match = RegExp(r'\[\[(.*?)\]\]').firstMatch(line);
        if (match != null) {
          currentCategory = match.group(1)!.trim();
          categories.putIfAbsent(currentCategory, () => []);
          currentIndentLevel = indentLevel;
        }
      } else if (line.contains('[[') && currentCategory.isNotEmpty && indentLevel > currentIndentLevel) {
        for (final match in RegExp(r'\[\[(.*?)\]\]').allMatches(line)) {
          final title = match.group(1)!.trim();
          if (!title.contains('http') && !title.startsWith('((') && !categories[currentCategory]!.contains(title)) {
            categories[currentCategory]!.add(title);
          }
        }
      }
    }
    return categories;
  }

  static String? _extractImageFromContent(String content) {
    final match = RegExp(r'!\[.*?\]\((.*?)\)').firstMatch(content);
    return match?.group(1);
  }

  /// 解析图片URL，将相对路径转换为完整的下载链接
  static Future<String?> _resolveImageUrl(String imageUrl, String articlePath) async {
    try {
      // 如果已经是完整URL，直接返回
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        return imageUrl;
      }

      // 获取文章所在目录
      final articleDir = articlePath.contains('/')
          ? articlePath.substring(0, articlePath.lastIndexOf('/'))
          : '';

      // 处理相对路径
      String resolvedPath = imageUrl;

      // 处理 ../ 路径
      if (imageUrl.startsWith('../')) {
        final parts = articleDir.split('/');
        var imgPath = imageUrl;
        while (imgPath.startsWith('../') && parts.isNotEmpty) {
          parts.removeLast();
          imgPath = imgPath.substring(3);
        }
        resolvedPath = parts.isEmpty ? imgPath : '${parts.join('/')}/$imgPath';
      }
      // 处理 ./ 路径
      else if (imageUrl.startsWith('./')) {
        resolvedPath = articleDir.isEmpty
            ? imageUrl.substring(2)
            : '$articleDir/${imageUrl.substring(2)}';
      }
      // 处理不带前缀的相对路径
      else if (!imageUrl.startsWith('/')) {
        resolvedPath = articleDir.isEmpty ? imageUrl : '$articleDir/$imageUrl';
      }

      // 清理路径中的多余斜杠
      resolvedPath = resolvedPath.replaceAll('//', '/');
      if (resolvedPath.startsWith('/')) {
        resolvedPath = resolvedPath.substring(1);
      }

      // 获取图片的下载链接
      final downloadUrl = await getImageContent(resolvedPath);
      return downloadUrl;
    } catch (e) {
      dev.log('解析图片URL失败: $imageUrl', name: 'UnifiedArticleService', error: e);
      return null;
    }
  }

  static String _extractExcerpt(String content) {
    final plainText = content
        .replaceAll(RegExp(r'#+\s+'), '')
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\[([^\]]*)\]\(.*?\)'), r'$1')
        .replaceAll(RegExp(r'`{1,3}[^`]*`{1,3}'), '')
        .replaceAll(RegExp(r'[*_]{1,2}([^*_]*)[*_]{1,2}'), r'$1')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();

    return plainText.length <= 200 ? plainText : '${plainText.substring(0, 200)}...';
  }
}
