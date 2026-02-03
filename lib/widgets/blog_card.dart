import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/unified_article.dart';
import '../services/unified_article_service.dart';

class BlogCard extends StatefulWidget {
  final UnifiedArticle post;

  const BlogCard({super.key, required this.post});

  @override
  State<BlogCard> createState() => _BlogCardState();
}

class _BlogCardState extends State<BlogCard> with SingleTickerProviderStateMixin {
  late final AnimationController _hoverController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _elevationAnimation;
  late UnifiedArticle _article;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _article = widget.post;
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOutCubic,
    ));
    _elevationAnimation = Tween<double>(
      begin: 2,
      end: 8,
    ).animate(CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeOutCubic,
    ));

    // 懒加载文章详情（包括真实图片）
    _loadArticleDetails();
  }

  Future<void> _loadArticleDetails() async {
    // 如果已有内容，说明已经加载过
    if (_article.content.isNotEmpty) return;

    setState(() {
      _isLoadingDetails = true;
    });

    try {
      final details = await UnifiedArticleService.getArticleDetails(_article);
      if (mounted) {
        setState(() {
          _article = details;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    super.dispose();
  }

  Widget _buildImage(BuildContext context) {
    final imageUrl = _article.imageUrl;
    final isPlaceholder = imageUrl.contains('picsum.photos');

    return Hero(
      tag: 'post-image-${_article.slug}',
      flightShuttleBuilder: (
        BuildContext flightContext,
        Animation<double> animation,
        HeroFlightDirection flightDirection,
        BuildContext fromHeroContext,
        BuildContext toHeroContext,
      ) {
        return AnimatedBuilder(
          animation: animation,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
          ),
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(
                  flightDirection == HeroFlightDirection.push
                      ? Tween<double>(begin: 12, end: 0).evaluate(animation)
                      : Tween<double>(begin: 0, end: 12).evaluate(animation),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            );
          },
        );
      },
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _isLoadingDetails && isPlaceholder
            ? _buildLoadingPlaceholder(context)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildErrorPlaceholder(context);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: child,
                    );
                  }
                  return _buildImageLoadingIndicator(context, loadingProgress);
                },
              ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '加载中...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '图片加载失败',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageLoadingIndicator(BuildContext context, ImageChunkEvent loadingProgress) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (loadingProgress.expectedTotalBytes != null) ...[
              const SizedBox(height: 8),
              Text(
                '${((loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!) * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTags(BuildContext context) {
    final tags = _article.tags.isNotEmpty
        ? _article.tags
        : (_article.categories.isNotEmpty ? _article.categories : [_article.category]);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.asMap().entries.map((entry) {
        final index = entry.key;
        final tag = entry.value;
        return AnimatedBuilder(
          animation: _hoverController,
          builder: (context, child) {
            final delay = index * 0.1;
            final offsetAnimation = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(0, -4),
            ).animate(
              CurvedAnimation(
                parent: _hoverController,
                curve: Interval(
                  delay.clamp(0.0, 1.0),
                  (delay + 0.4).clamp(0.0, 1.0),
                  curve: Curves.easeOutCubic,
                ),
              ),
            );
            return Transform.translate(
              offset: offsetAnimation.value,
              child: child,
            );
          },
          child: Chip(
            label: Text(
              tag,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hoverController.forward(),
      onExit: (_) => _hoverController.reverse(),
      child: AnimatedBuilder(
        animation: _hoverController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Card(
              clipBehavior: Clip.antiAlias,
              elevation: _elevationAnimation.value,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
          );
        },
        child: InkWell(
          onTap: () => context.go('/article/page', extra: {
            'path': '${_article.path}',
            'name': _article.title,
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImage(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _article.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _article.excerpt.isNotEmpty ? _article.excerpt : _article.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _article.author.isNotEmpty ? _article.author : "未知作者",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getDateText(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTags(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDateText() {
    // 优先使用 publishDate
    if (_article.publishDate != null) {
      return _formatDate(_article.publishDate!);
    }
    // 其次尝试解析 commitDate
    if (_article.commitDate.isNotEmpty) {
      final date = DateTime.tryParse(_article.commitDate);
      if (date != null) return _formatDate(date);
    }
    // 未加载时显示占位符
    return '---';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
