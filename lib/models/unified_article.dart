import 'dart:convert';

/// 统一的文章模型，整合了原来的 Article、CategoryArticle 和 BlogPost 的所有字段
class UnifiedArticle {
  // 基本信息
  final String name;           // 文章名称
  final String title;          // 文章标题
  final String description;    // 文章描述
  final String excerpt;        // 文章摘要
  final String content;        // 文章内容
  
  // 分类和标签
  final String category;       // 文章分类
  final List<String> tags;     // 文章标签
  final List<String> categories; // 多分类支持
  
  // 文件和路径信息
  final String path;           // 文件路径
  final String downloadUrl;    // 下载链接
  final String slug;           // URL友好的标识
  final String sha;            // Git SHA
  final int size;              // 文件大小
  final String type;           // 文件类型
  
  // 时间和作者信息
  final String date;           // 发布日期字符串
  final String commitDate;     // 提交日期字符串（空字符串表示未加载）
  final DateTime? publishDate; // 发布日期对象（null 表示未加载）
  final String author;         // 作者
  
  // 媒体信息
  final String imageUrl;       // 封面图片URL

  UnifiedArticle({
    required this.name,
    required this.title,
    required this.path,
    required this.downloadUrl,
    this.description = '',
    this.excerpt = '',
    this.content = '',
    this.category = '',
    this.tags = const [],
    this.categories = const [],
    this.slug = '',
    this.sha = '',
    this.size = 0,
    this.type = 'file',
    this.date = '',
    this.commitDate = '',
    this.publishDate,
    this.author = '',
    this.imageUrl = 'https://picsum.photos/800/400',
  });

  /// 从 JSON 创建 UnifiedArticle 对象
  factory UnifiedArticle.fromJson(Map<String, dynamic> json) {
    return UnifiedArticle(
      name: json['name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      path: json['path'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
      excerpt: json['excerpt'] as String? ?? '',
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? '',
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      categories: json['categories'] != null ? List<String>.from(json['categories']) : [],
      slug: json['slug'] as String? ?? '',
      sha: json['sha'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      type: json['type'] as String? ?? 'file',
      date: json['date'] as String? ?? '',
      commitDate: json['commitDate'] as String? ?? '',
      publishDate: json['publishDate'] != null ? DateTime.parse(json['publishDate'] as String) : null,
      author: json['author'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? 'https://picsum.photos/800/400',
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'title': title,
      'path': path,
      'downloadUrl': downloadUrl,
      'description': description,
      'excerpt': excerpt,
      'content': content,
      'category': category,
      'tags': tags,
      'categories': categories,
      'slug': slug,
      'sha': sha,
      'size': size,
      'type': type,
      'date': date,
      'commitDate': commitDate,
      'publishDate': publishDate?.toIso8601String(),
      'author': author,
      'imageUrl': imageUrl,
    };
  }
}

class ArticleCategory {
  final String name;
  final List<UnifiedArticle> articles;

  ArticleCategory({
    required this.name,
    required this.articles,
  });
} 