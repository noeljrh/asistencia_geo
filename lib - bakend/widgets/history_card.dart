import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HistoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? mapsUrl;
  final String? status; // PENDIENTE, REINTENTANDO, FALLIDO, ENVIADO
  final VoidCallback? onDetails;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  const HistoryCard({
    Key? key,
    required this.title,
    required this.subtitle,
    this.mapsUrl,
    this.status,
    this.onDetails,
    this.onDelete,
    this.onRetry,
  }) : super(key: key);

  Future<void> _openMaps(BuildContext context) async {
    if (mapsUrl == null || mapsUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay URL de mapa disponible')));
      return;
    }
    final uri = Uri.tryParse(mapsUrl!);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL de mapa inválida')));
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se puede abrir el mapa')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error abriendo mapa: ${e.toString()}')));
    }
  }

  Color? _statusColor() {
    switch (status) {
      case 'PENDIENTE':
        return Colors.orange;
      case 'REINTENTANDO':
        return Colors.amber;
      case 'FALLIDO':
        return Colors.redAccent;
      case 'ENVIADO':
        return Colors.green;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMap = mapsUrl != null && mapsUrl!.trim().isNotEmpty;
    final statusColor = _statusColor();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Icon(Icons.location_on, color: Colors.white, size: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                      if (status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor?.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(status!, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                if (hasMap)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ElevatedButton.icon(
                      onPressed: () => _openMaps(context),
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('Ver mapa'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                if (status == 'PENDIENTE' || status == 'REINTENTANDO' || status == 'FALLIDO')
                  IconButton(
                    tooltip: 'Reintentar',
                    icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                    onPressed: onRetry,
                  ),
                IconButton(
                  tooltip: 'Detalles',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: onDetails,
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
