import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:karst_app/weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:karst_app/models/cave.dart';
import 'dart:convert';
import 'dart:math';
import 'models/review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart'; // Import intl package for date formatting
import 'package:csv/csv.dart'; // Import the csv package
import 'package:karst_app/notification_service.dart'; // Import the notification service
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:karst_app/background_service.dart'; // Import the background service
import 'package:karst_app/ar_cave_map.dart'; // Import the AR cave map
import 'package:karst_app/point_cloud_viewer.dart';

// Add this extension method at the top of your file, after the imports
extension StringCasingExtension on String {
  String toCapitalized() => length > 0 ? '${this[0].toUpperCase()}${substring(1).toLowerCase()}' : '';
}

// Move method outside of extension
Widget _buildEquipmentList(String equipment) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: equipment.split(',').map((item) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(child: Text(item.trim())),
          ],
        ),
      );
    }).toList(),
  );
}

Color _getDifficultyColor(String? difficulty) {
  switch (difficulty?.toLowerCase()) {
    case 'easy':
      return Colors.green;
    case 'moderate':
      return Colors.orange;
    case 'difficult':
    case 'advanced':
    case 'expert':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

// Define the missing method
Widget _buildSafetyThresholdLegend() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Safe'),
        ]
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Caution'),
        ]
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          const Text('Danger'),
        ],
      ),
    ],
  );
}

// Add at the top of your file
class CaveColors {
  static const primary = Color(0xFF1565C0);
  static const secondary = Color(0xFF26A69A);
  static const background = Color(0xFFF5F7FA);
  static const cardBackground = Colors.white;
  static const textPrimary = Color(0xFF2D3748);
  static const textSecondary = Color(0xFF718096);
  static const danger = Color(0xFFE53E3E);
  static const warning = Color(0xFFECC94B);
  static const success = Color(0xFF48BB78);
  static const info = Color(0xFF4299E1);
}

// Separate method for building error view
Widget _buildErrorView() {
  return const Center(
    child: Text(
      'An error occurred while fetching data.',
      style: TextStyle(color: Colors.red, fontSize: 18),
    ),
  );
}

// Add this helper method for safe conversion of values to double
double _parseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    try {
      return double.parse(value);
    } catch (e) {
      return 0.0;
    }
  }
  return 0.0;
}

// Add this helper method to safely parse weather data
double _safeGetTemperature(Map<String, dynamic>? data, String key) {
  if (data == null) return 0.0;
  return _parseDouble(data['main']?[key] ?? 0.0);
}

class CaveDetailScreen extends StatefulWidget {
  final Cave cave;

  const CaveDetailScreen({super.key, required this.cave});

  @override
  State<CaveDetailScreen> createState() => _CaveDetailScreenState();
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  double get maxExtent => _tabBar.preferredSize.height;
  
  @override
  double get minExtent => _tabBar.preferredSize.height;
  
  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return _tabBar != oldDelegate._tabBar;
  }
}

// Global reference to the current state for static methods
_CaveDetailScreenState? _currentState;

class _CaveDetailScreenState extends State<CaveDetailScreen> {

  // Define the missing method
  Widget buildSurveyGradeVisual(String grade) {
    // Implement your logic to build the survey grade visual
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Text(
        'Survey Grade: $grade',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }
  // Define the missing method
  Widget buildSurveyDetailItem({required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(value),
      ],
    );
  }

  // Add this to properly handle state reference
  @override
  void initState() {
    super.initState();
    _currentState = this;
  }

  @override
  void dispose() {
    _currentState = null;
    super.dispose();
  }

  List<dynamic>? forecastData;
  Map<String, dynamic>? weatherData;
  final int _rating = 0;
  Map<String, dynamic>? githubCaveData; // Define githubCaveData here
  late TabController _tabController;
  bool isFavorite = false;
  bool isLoading = true;
  bool hasError = false;
  bool _weatherAlertsEnabled = false;
  final TextEditingController _reviewController = TextEditingController();
  final TextEditingController _visitNotesController = TextEditingController();
  List<Review> reviews = []; // Initialize empty reviews list
  bool _isMonitored = false;

  Future<void> _checkIfMonitored() async {
    // Implement your logic to check if the cave is monitored
    // For example, you can fetch data from a database or an API
    // and update the _isMonitored variable accordingly.
    // This is just a placeholder implementation.
    setState(() {
      _isMonitored = true; // or false based on your logic
    });
  }

  Widget buildSafetyLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  Widget buildSurveyInfoSection() {
    if (githubCaveData == null || 
        !githubCaveData!.containsKey('SurveyGrade') ||
        githubCaveData!['SurveyGrade'].toString().isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        buildSectionHeader('Survey Information', Icons.straighten, Colors.blue),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    buildSurveyGradeVisual(githubCaveData!['SurveyGrade'].toString()),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Grade ${githubCaveData!['SurveyGrade']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            getSurveyGradeDescription(githubCaveData!['SurveyGrade'].toString()),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // Survey details in a grid
                Row(
                  children: [
                    Expanded(
                      child: buildSurveyDetailItem(
                        icon: Icons.calendar_today,
                        label: 'Survey Date',
                        value: githubCaveData!['SurveyDate'] ?? 'Unknown',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildSurveyDetailItem(
                        icon: Icons.people,
                        label: 'Survey Team',
                        value: githubCaveData!['SurveyTeam'] ?? 'Unknown',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: buildSurveyDetailItem(
                        icon: Icons.straighten,
                        label: 'Length',
                        value: githubCaveData!['Length'] ?? 'Unknown',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildSurveyDetailItem(
                        icon: Icons.height,
                        label: 'Vertical Extent',
                        value: githubCaveData!['VerticalExtent'] ?? 'Unknown',
                      ),
                    ),
                  ],
                ),
                
                // Survey notes
                if (githubCaveData!.containsKey('SurveyNotes') && 
                   githubCaveData!['SurveyNotes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Survey Notes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    githubCaveData!['SurveyNotes'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSeasonalSafetyGraph() {
    final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Seasonal Safety Ratings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  barGroups: generateSeasonalBarGroups(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < months.length) {
                            return Text(months[index]);
                          }
                          return const Text('');
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 2,
                        getTitlesWidget: (value, meta) {
                          return Text(value.toInt().toString());
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  maxY: 10,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Safety Rating Index: Lower values indicate safer conditions',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildSafetyLegendItem(Colors.green, 'Low Risk'),
                const SizedBox(width: 16),
                buildSafetyLegendItem(Colors.orange, 'Medium Risk'),
                const SizedBox(width: 16),
                buildSafetyLegendItem(Colors.red, 'High Risk'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> generateSeasonalBarGroups() {
    // Implement your logic to generate bar groups for the seasonal safety graph
    return List.generate(12, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: Random().nextDouble() * 10,
            color: index < 4 ? Colors.green : (index < 8 ? Colors.orange : Colors.red),
          ),
        ],
      );
    });
  }

  double calculateCurrentAirflow() {
    // Implement your logic to calculate the current airflow
    // This is just a placeholder implementation
    return Random().nextDouble() * 2 - 1; // Random value between -1 and 1
  }

  Widget buildAirflowExplanation() {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: Text(
        'Airflow in caves can be influenced by various factors including external weather conditions, cave geometry, and temperature differences between the cave interior and the outside environment.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
    );
  }

  Widget buildCaveBreathingForecast() {
    final currentAirflow = calculateCurrentAirflow();
    final bool isInflow = currentAirflow < 0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInflow ? Icons.south : Icons.north,
                  color: Colors.purple,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cave Breathing Forecast',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isInflow ? Icons.arrow_downward : Icons.arrow_upward,
                    color: Colors.purple,
                    size: 48,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isInflow ? 'Currently: Inward Airflow' : 'Currently: Outward Airflow',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isInflow 
                  ? 'Cold air entering the cave system'
                  : 'Warm air exiting the cave system',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            buildAirflowExplanation(),
          ],
        ),
      ),
    );
  }

  Future<void> checkIfFavorite() async {
    final user = Supabase.instance.client.auth.currentUser;
  }

  @override
  void dispose() {
    // Clear global state reference
    if (_currentState == this) {
      _currentState = null;
    }
    _tabController.dispose();
    _reviewController.dispose();
    _visitNotesController.dispose();
    super.dispose();
  } // Remove the duplicate dispose method below

  Future<void> checkIfFavorite() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final response = await Supabase.instance.client
            .from('favorites')
            .select()
            .eq('user_id', user.id)
            .eq('cave_name', widget.cave.name)
            .single();

        setState(() {
          isFavorite = response != null;
        });
      } catch (e) {
        setState(() {
          isFavorite = false;
        });
      }
    }
  }

  Future<void> toggleFavorite() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        if (isFavorite) {
          await Supabase.instance.client.from('favorites').delete().match({
            'user_id': user.id,
            'cave_name': widget.cave.name
          });
        } else {
          await Supabase.instance.client.from('favorites').insert({
            'user_id': user.id,
            'cave_name': widget.cave.name,
            'description': widget.cave.description,
            'latitude': widget.cave.location.latitude,
            'longitude': widget.cave.location.longitude,
          });
        }
        setState(() {
          isFavorite = !isFavorite;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating favorite: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to favorite caves')),
      );
    }
  }

  Future<void> _loadWeatherAlertPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weatherAlertsEnabled = prefs.getBool('weather_alerts_enabled') ?? false;
    });
  }

  Future<void> _fetchWeather() async {
  try {
    setState(() => isLoading = true);
    
    // Get coordinates from the specific cave
    final latitude = widget.cave.location.latitude;
    final longitude = widget.cave.location.longitude;
    
    print('Fetching weather for: $latitude, $longitude');
    
    final currentData = await WeatherService.getWeather(LatLng(widget.cave.location.latitude, widget.cave.location.longitude));
    final forecastData = await WeatherService.getWeatherForecast(widget.cave.location.latitude, widget.cave.location.longitude);

    print('Current weather data received: ${currentData != null}');
    print('Forecast data received: ${forecastData.length} items');

    // Process forecast data to get AM/PM averages for 7 days
    List<Map<String, dynamic>> processedForecast = [];
    
    if (forecastData.isNotEmpty) {
      // Group forecast by days
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final targetDate = now.add(Duration(days: i));
        final dayForecasts = forecastData.where((f) {
          final forecastDate = DateTime.parse(f['dt_txt']);
          return forecastDate.day == targetDate.day && 
                 forecastDate.month == targetDate.month;
        }).toList();

        if (dayForecasts.isNotEmpty) {
          final amForecasts = dayForecasts
              .where((f) => DateTime.parse(f['dt_txt']).hour < 12)
              .toList();
          final pmForecasts = dayForecasts
              .where((f) => DateTime.parse(f['dt_txt']).hour >= 12 && DateTime.parse(f['dt_txt']).hour < 18)
              .toList();
          final eveningForecasts = dayForecasts
              .where((f) => DateTime.parse(f['dt_txt']).hour >= 18)
              .toList();

          processedForecast.add({
            'date': targetDate.toString().split(' ')[0],
            'amTemp': _calculateAverage(amForecasts, 'main', 'temp'),
            'pmTemp': _calculateAverage(pmForecasts, 'main', 'temp'),
            'eveningTemp': _calculateAverage(eveningForecasts, 'main', 'temp'),
            'avgHumidity': _calculateAverage(dayForecasts, 'main', 'humidity'),
            'avgWindSpeed': _calculateAverage(dayForecasts, 'wind', 'speed'),
            'weather': dayForecasts.isNotEmpty ? dayForecasts[dayForecasts.length ~/ 2]['weather'][0] : null,
          });
        }
      }
    }
  
    setState(() {
      weatherData = currentData; // currentData is already a Map<String, dynamic>
      this.forecastData = processedForecast;
      isLoading = false;
      hasError = false;
    });
    
    // Save weather data to cache for offline access
    _saveCacheData();
    
  } catch (e) {
    print('Error fetching weather: $e');
    setState(() {
      hasError = true;
      isLoading = false;
    });
    
    // Try to load cached data if network request fails
    _loadCachedData();
  }
}

  double _calculateAverage(List<dynamic> forecasts, String key1, String key2) {
    if (forecasts.isEmpty) return 0.0;
    final sum = forecasts.fold<double>(
        0.0, (sum, item) => sum + (item[key1][key2] as num).toDouble());
    return sum / forecasts.length;
  }

  Future<void> _fetchGithubCaveData() async {
    const url = 'https://raw.githubusercontent.com/CaveSurveys/Karst_Caves/main/karstdatabase.csv';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print("CSV Data received, size: ${response.body.length} bytes");
        final csvData = response.body;
        
        // Parse CSV with proper headers
        List<List<dynamic>> rowsAsListOfValues = const CsvToListConverter().convert(csvData);
        
        if (rowsAsListOfValues.isEmpty) {
          print('Error: CSV file is empty');
          setState(() {
            githubCaveData = {};
          });
          return;
        }
        
        // Get headers from first row
        final List<String> headers = rowsAsListOfValues[0].map((e) => e.toString().trim()).toList();
        print("CSV Headers: $headers");
        
        // Normalize the cave name for comparison
        String normalizedCaveName = widget.cave.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        
        // Search for matching cave
        for (var i = 1; i < rowsAsListOfValues.length; i++) {
          final List<dynamic> row = rowsAsListOfValues[i];
          if (row.length < 3) continue; // Make sure we have at least the name column
          
          String normalizedRowName = row[2].toString() // Name is in column 3
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          
          if (normalizedRowName == normalizedCaveName) {
            // Map all available columns - ensure everything is converted to String
            final Map<String, dynamic> caveData = {};
            for (int j = 0; j < row.length && j < headers.length; j++) {
              // Convert all values to strings to avoid type issues
              caveData[headers[j]] = row[j].toString();
            }

            // Add point cloud data if available
            if (widget.cave.name.contains('Long Churn')) {
              caveData['PointCloudURL'] = 'https://raw.githubusercontent.com/CaveSurveys/Upper-Long-Churn/refs/heads/main/Upper%20Long%20Churns%20-%20Pointcloud.xyz';
            } else {
              caveData['PointCloudURL'] = null;
            }

            setState(() {
              githubCaveData = caveData;
            });
            return;
          }
        }
        
        // No matching cave found
        setState(() {
          githubCaveData = {};
        });
      } else {
        print('Error fetching CSV data: ${response.statusCode}');
        setState(() {
          githubCaveData = {};
        });
      }
    } catch (e) {
      print('Error fetching GitHub CSV data: $e');
      setState(() {
        githubCaveData = {};
      });
    }
  }

  Future<void> _fetchReviews() async {
    // Implement your review fetching logic here
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('cave_reviews')
            .select()
            .eq('cave_name', widget.cave.name)
            .order('created_at', ascending: false);
        
        setState(() {
          reviews = List<Review>.from(
            response.map((review) => Review.fromMap(review))
          );
        });
            }
    } catch (e) {
      print('Error fetching reviews: $e');
    }
  }Future<void> _saveCacheData() async {
    final prefs = await SharedPreferences.getInstance();
  Future<void> saveCacheData() async {
    final prefs = await SharedPreferences.getInstance();
    if (weatherData != null) {
      await prefs.setString('weather_${widget.cave.name}', jsonEncode(weatherData));
      await prefs.setInt('weather_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
    }
      await prefs.setString('weather_${widget.cave.name}', jsonEncode(weatherData));
      await prefs.setInt('weather_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
    } await prefs.setString('cave_data_${widget.cave.name}', jsonEncode(githubCaveData));
    if (githubCaveData != null) {
      await prefs.setString('cave_data_${widget.cave.name}', jsonEncode(githubCaveData));
      await prefs.setInt('cave_data_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
    }
      await prefs.setString('cave_data_${widget.cave.name}', jsonEncode(githubCaveData));
      await prefs.setInt('cave_data_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
      return null;
    }
  }Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
  Future<void> loadCachedData() async {g('weather_${widget.cave.name}');
    final prefs = await SharedPreferences.getInstance();
    final weatherString = prefs.getString('weather_${widget.cave.name}');
    final weatherTimestamp = prefs.getInt('weather_timestamp_${widget.cave.name}');
      final timeDiff = DateTime.now().millisecondsSinceEpoch - weatherTimestamp;
    if (weatherString != null && weatherTimestamp != null) {
      final timeDiff = DateTime.now().millisecondsSinceEpoch - weatherTimestamp;
      if (timeDiff < const Duration(hours: 1).inMilliseconds) {
        setState(() {
          weatherData = jsonDecode(weatherString);
        });
      }
    }
  }

  Future<void> fetchReviews() async {
    // Implement your review fetching logic here
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final response = await Supabase.instance.client
            .from('cave_reviews')
            .select()
            .eq('cave_name', widget.cave.name)
            .order('created_at', ascending: false);
        
        setState(() {
          reviews = List<Review>.from(
            response.map((review) => Review.fromMap(review))
          );
        });
      }
    } catch (e) {
      print('Error fetching reviews: $e');
    }
  }
  
  Future<void> saveCacheData() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (weatherData != null) {
      await prefs.setString('weather_${widget.cave.name}', jsonEncode(weatherData));
      await prefs.setInt('weather_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
    }
    
    if (githubCaveData != null) {
      await prefs.setString('cave_data_${widget.cave.name}', jsonEncode(githubCaveData));
      await prefs.setInt('cave_data_timestamp_${widget.cave.name}', DateTime.now().millisecondsSinceEpoch);
    }
  }
  
  Future<void> loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final weatherString = prefs.getString('weather_${widget.cave.name}');
    final weatherTimestamp = prefs.getInt('weather_timestamp_${widget.cave.name}');
    
    if (weatherString != null && weatherTimestamp != null) {
      final timeDiff = DateTime.now().millisecondsSinceEpoch - weatherTimestamp;
      if (timeDiff < const Duration(hours: 1).inMilliseconds) {
        setState(() {
          weatherData = jsonDecode(weatherString);
        });
      }
    }
    
    final caveDataString = prefs.getString('cave_data_${widget.cave.name}');
    final caveDataTimestamp = prefs.getInt('cave_data_timestamp_${widget.cave.name}');
    
    if (caveDataString != null && caveDataTimestamp != null) {
      setState(() {
        githubCaveData = jsonDecode(caveDataString);
      });
    }
  }
  
  Future<void> checkWeatherAlerts() async {
    if (weatherData != null) {
      final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase();
      if (conditions != null && (conditions.contains('rain') || conditions.contains('storm'))) {
        NotificationService.showNotification(
          title: 'Weather Alert for ${widget.cave.name}',
          body: 'Adverse weather conditions detected. Check weather tab for details.',
          payload: jsonEncode({'caveName': widget.cave.name}),
        );
      }
    }
  }
  
  Future<void> setupWeatherAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final alertTypes = <String>{
      'rain',
      'storm',
      'flood',
      'snow',
      'extreme',
    };
    
    if (weatherData != null) {
      for (final alertType in alertTypes) {
        if (shouldShowAlert(alertType)) {
          final lastAlertTime = prefs.getInt('last_${alertType}_alert') ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          if (now - lastAlertTime > const Duration(hours: 6).inMilliseconds) {
            await NotificationService.showNotification(
              title: 'Weather Alert: ${alertType.toUpperCase()}',
              body: 'Potentially dangerous conditions detected for ${widget.cave.name}',
              payload: jsonEncode({'caveName': widget.cave.name}),
            );
            await prefs.setInt('last_${alertType}_alert', now);
          }
        }
      }
    }
  }
  
  bool shouldShowAlert(String alertType) {
    if (weatherData == null) return false;
    
    final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase();
    return conditions != null && conditions.contains(alertType);
  }
  
  Future<void> clearOldCache() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = prefs.getKeys();
    
    for (final key in keys) {
      if (key.startsWith('weather_timestamp_')) {
        final timestamp = prefs.getInt(key) ?? 0;
        if (now - timestamp > const Duration(days: 7).inMilliseconds) {
          await prefs.remove(key);
          await prefs.remove(key.replaceFirst('timestamp_', ''));
        }
      }
    }
  }
  
  Widget buildLoadingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
  
  Widget buildInfoCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
  
  Widget buildEmptyCard(String message) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
  
  Widget buildConservationStatusCard(String status) {
    // Print debug info
    print('Building conservation status card with: $status');
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conservation Status:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget buildCustomInfoCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
  Widget buildInfoRow(IconData icon, String label, String value, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDivider() {
    return const Divider(
      height: 16,
      thickness: 1,
    );
  }
    // Colors for a clean, modern design
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color textColor = Colors.grey[800]!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero card with cave image and name
          Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cave image (placeholder or actual cave image if available)
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/cave_placeholder.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Chip(
                      backgroundColor: primaryColor.withOpacity(0.9),
                      label: Text(
                        githubCaveData?['DifficultyLevel'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                // Cave details
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.cave.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        githubCaveData?['ShortDescription'] ?? widget.cave.description,
                        style: TextStyle(
                          fontSize: 15,
                          color: textColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          // New Summary Card with key information in grid format
          buildOverviewSummaryCard(),
          
          const SizedBox(height: 24),
          // Quick Stats Section with modern cards
          Row(
            children: [
              buildQuickStatCard(
                icon: Icons.height,
                title: 'Depth',
                value: githubCaveData?['Depth'] ?? 'Unknown',
                color: Colors.green,
              ),
              const SizedBox(width: 16),
              buildQuickStatCard(
                icon: Icons.calendar_today,
                title: 'Discovered',
                value: githubCaveData?['DiscoveryYear'] ?? 'Unknown',
                color: Colors.purple,
              ),
            ],
          ),
          // Rest of the existing sections
          const SizedBox(height: 24),
          buildSectionHeader('About This Cave', Icons.description, primaryColor),
          const SizedBox(height: 16),
          // Additional information section
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    githubCaveData?['DetailedDescription'] ?? 
                    'This cave is part of the local karst system. More detailed information about formation, history, and notable features will be displayed here when available.',
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      height: 1.5,
                    ),
                  ),
                  if (githubCaveData?['HistoricalSignificance'] != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Historical Significance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      githubCaveData!['HistoricalSignificance'],
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Conservation status section
          const SizedBox(height: 24),
          buildSectionHeader('Conservation Status', Icons.eco, Colors.green),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.eco,
                        color: Colors.green,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        githubCaveData?['ConservationStatus'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    githubCaveData?['ConservationNotes'] ?? 
                    'Please respect cave conservation principles during your visit. Take nothing but pictures, leave nothing but footprints, kill nothing but time.',
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Equipment recommendations
          const SizedBox(height: 24),
          buildSectionHeader('Recommended Equipment', Icons.backpack, Colors.orange),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  githubCaveData?['Equipment'] != null
                      ? Text(githubCaveData!['Equipment'])
                      : Text(
                          'No specific equipment recommendations available.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  Widget buildQuickStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget buildTechnicalTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Technical Summary Card with difficulty visualization
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Column(
              children: [
                // Technical difficulty visualization
                Container(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      buildDifficultyIndicator(githubCaveData?['DifficultyLevel']),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Technical Difficulty',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              githubCaveData?['DifficultyLevel'] ?? 'Not specified',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              getDifficultyDescription(githubCaveData?['DifficultyLevel']),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          // Enhanced technical details with all CSV categories
          buildEnhancedTechnicalInfo(),
          
          const SizedBox(height: 24),
          // SRT Information with interactive elements - keep this section
          if (githubCaveData != null && githubCaveData!.containsKey('SRT')) ...[
            buildModernSectionHeader('SRT Information', Icons.alt_route),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 1,
              child: const Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Existing SRT content...
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget buildModernSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget buildDifficultyIndicator(String? difficulty) {
    final Color color = _getDifficultyColor(difficulty);
    final int level = getDifficultyLevel(difficulty);
    
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              level.toString(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              'Level',
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }  int getDifficultyLevel(String? difficulty) {
    if (difficulty == null) return 1;
    
    final String lowercased = difficulty.toLowerCase();
    if (lowercased.contains('easy') || lowercased.contains('beginner')) {
      return 1;
    } else if (lowercased.contains('moderate') || lowercased.contains('intermediate')) {
      return 2;
    } else if (lowercased.contains('difficult') || lowercased.contains('hard')) {
      return 3;
    } else if (lowercased.contains('expert') || lowercased.contains('advanced')) {
      return 4;
    } else {
      return 1;
    }
  }
  
  String getDifficultyDescription(String? difficulty) {
    if (difficulty == null) return 'No difficulty information available.';
    
    final String lowercased = difficulty.toLowerCase();
    if (lowercased.contains('easy') || lowercased.contains('beginner')) {
      return 'Suitable for beginners with basic caving knowledge.';
    } else if (lowercased.contains('moderate') || lowercased.contains('intermediate')) {
      return 'Requires some experience and moderate physical fitness.';
    } else if (lowercased.contains('difficult') || lowercased.contains('hard')) {
      return 'Challenging route requiring significant experience and good physical condition.';
    } else if (lowercased.contains('expert') || lowercased.contains('advanced')) {
      return 'For experienced cavers only. Technically demanding with potential hazards.';
    } else {
      return 'Specific difficulty information not available.';
    }
  }
  
  Widget buildTechSpecRow({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.blue, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? Colors.grey[800],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget buildLocationTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader('Map', Icons.map, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(widget.cave.location.latitude, widget.cave.location.longitude),
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(widget.cave.location.latitude, widget.cave.location.longitude),
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          buildSectionHeader('Directions', Icons.directions, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Coordinates: ${widget.cave.location.latitude}, ${widget.cave.location.longitude}'),
                  const SizedBox(height: 8),
                  Text(githubCaveData?['DirectionsToEntrance'] ?? 'No directions available'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ARCaveMapView(
                      cave: widget.cave,
                      caveData: githubCaveData,
                      tunnelData: getTunnelData(), // Implement this method to extract tunnel coordinates
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.view_in_ar),
              label: const Text('View Cave in AR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              ),
            ),
          ),
          // Add buttons for AR and 3D point cloud visualization
          Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ARCaveMapView(
                            cave: widget.cave,
                            caveData: githubCaveData,
                            tunnelData: getTunnelData(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.view_in_ar),
                    label: const Text('AR Cave Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // New button to view 3D point cloud
                if (githubCaveData != null && 
                    githubCaveData!.containsKey('PointCloudURL') && 
                    githubCaveData!['PointCloudURL'].toString().isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Skip to the 3D model tab
                        _tabController.animateTo(6); // Index of 3D Model tab
                      },
                      icon: const Icon(Icons.cloud),
                      label: const Text('3D Point Cloud'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget buildSafetySummary() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  'Safety Alert',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Current weather conditions indicate potential hazards. Please exercise caution.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget buildCurrentWeatherDetails() {
    return Column(
      children: [
        buildDetailRow(
          icon: Icons.thermostat,
          label: 'Temperature',
          value: '${weatherData!['main']['temp']}°C',
        ),
        buildDetailRow(
          icon: Icons.water_drop,
          label: 'Humidity',
          value: '${weatherData!['main']['humidity']}%',
        ),
        buildDetailRow(
          icon: Icons.air,
          label: 'Wind Speed',
          value: '${weatherData!['wind']['speed']} m/s',
        ),
      ],
    );
  }
  
  Widget buildWeatherInfoCard() {
    if (weatherData == null) return buildEmptyCard('No weather data available');
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                getWeatherIcon(weatherData!['weather'][0]['main'].toString(), context),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weatherData!['weather'][0]['description'].toString().toCapitalized(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${weatherData!['main']['temp'].toString()}°C',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            buildCurrentWeatherDetails(),
          ],
        ),
      ),
    );
  }
  
  Widget buildDetailRow({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget buildWeatherTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Rest of your existing implementation
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Critical alert for rain/flood risk at the very top
          if (hasRainWarning0() || hasFloodRisk()) buildCriticalRainWarning(),
          
          // Current weather section with prominent display
          buildSectionHeader('Current Weather', Icons.wb_sunny, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          buildEnhancedWeatherInfoCard(),
          
          const SizedBox(height: 24),
          // Cave flood risk assessment - high priority due to safety concerns
          buildSectionHeader('Cave Flood Risk Assessment', Icons.warning, Colors.blue.shade800),
          const SizedBox(height: 12),
          buildCaveImpactCard(),
          
          const SizedBox(height: 24),
          // Precipitation forecast - important for planning
          buildSectionHeader('Precipitation Forecast', Icons.water_drop, Colors.blue),
          const SizedBox(height: 12),
          buildPrecipitationChart(),
          
          const SizedBox(height: 24),
          // 7-day forecast
          buildSectionHeader('7-Day Forecast', Icons.calendar_today, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          _buildEnhancedForecastCards(),
          
          const SizedBox(height: 24),
          // Temperature trend
          buildSectionHeader('Temperature Trend', Icons.thermostat, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          buildTemperatureChart(),
          
          const SizedBox(height: 24),
          // Safety recommendations
          buildSectionHeader('Safety Recommendations', Icons.shield, Colors.orange),
          const SizedBox(height: 12),
          buildEnhancedSafetyRecommendations(),
          
          const SizedBox(height: 24),
          // Weather alert settings at the bottom
          buildWeatherAlertSettings(),
          
          const SizedBox(height: 24),
          // Cave breathing forecast
          buildCaveBreathingForecast(),
          
          const SizedBox(height: 24),
          // Seasonal safety graph
          buildSeasonalSafetyGraph(),
        ],
      ),
    );
  }
  
  Widget buildCriticalRainWarning() {
    // Get weather description and precipitation
    final weatherDesc = weatherData?['weather']?[0]?['description']?.toString().toCapitalized() ?? 'Unknown';
    final precipitation = getPrecipitation1h();
    
    return Card(
      elevation: 3,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300, width: 1.5),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CAVE FLOOD RISK ALERT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current conditions: $weatherDesc ($precipitation mm/h)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    githubCaveData?['FloodRisk'] != null 
                        ? 'This cave has ${githubCaveData!["FloodRisk"]} flood risk. Current precipitation may create dangerous conditions.'
                        : 'Current precipitation may create dangerous conditions in this cave system.',
                    style: TextStyle(
                      fontSize: 14, 
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time_filled, size: 14, color: Colors.red.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Estimated runoff time: ${WeatherUtils.calculateRunoffTime(WeatherUtils.calculateRainIntensity(weatherData))}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }  Widget buildEnhancedWeatherInfoCard() {
    if (weatherData == null) return buildEmptyCard('No weather data available');
    
    final weatherDesc = weatherData!['weather'][0]['description'].toString().toCapitalized();
    final weatherMain = weatherData!['weather'][0]['main'].toString();
    final temp = _parseDouble(weatherData!['main']['temp']);
    final feelsLike = _parseDouble(weatherData!['main']['feels_like']);
    final humidity = _parseDouble(weatherData!['main']['humidity']);
    
    // Calculate safety index based on current conditions
    final safetyIndex = calculateWeatherSafetyIndex();
    final safetyColor = getSafetyColor(safetyIndex);
    final safetyText = getSafetyText(safetyIndex);
    
    // Calculate chance of rain (probability of precipitation)
    final double rainChance = _parseDouble(weatherData!['rain_probability'] ?? 0.0) * 100;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with large weather icon and temperature
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: getWeatherBackgroundColor(weatherMain).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                getLargeWeatherIcon(weatherMain),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weatherDesc,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${temp.toStringAsFixed(1)}°',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Feels like ${feelsLike.toStringAsFixed(1)}°',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Safety indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: safetyColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: safetyColor),
                  ),
                  child: Text(
                    safetyText,
                    style: TextStyle(
                      color: safetyColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Highlight precipitation if present (added prominence)
          if (hasPrecipitation()) 
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.umbrella, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Precipitation: ${getPrecipitation1h()} mm/h',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'Rain chance: ${rainChance.round()}%',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          
          // Weather details in a more organized grid
          Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    buildWeatherDetailItem(
                      icon: Icons.water_drop,
                      label: 'Humidity',
                      value: '$humidity%',
                    ),
                    const SizedBox(width: 24),
                    buildWeatherDetailItem(
                      icon: Icons.air,
                      label: 'Wind',
                      value: '${weatherData!['wind']['speed']} m/s',
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    buildWeatherDetailItem(
                      icon: Icons.visibility,
                      label: 'Visibility',
                      value: '${(weatherData!['visibility'] as int) ~/ 1000} km',
                    ),
                    const SizedBox(width: 24),
                    buildWeatherDetailItem(
                      icon: Icons.compress,
                      label: 'Pressure',
                      value: '${weatherData!['main']['pressure']} hPa',
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Divider and update time
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Last updated: ${DateFormat('h:mm a').format(DateTime.now())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _fetchWeather,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget buildCommunityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader('Reviews', Icons.star, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          reviews.isEmpty
              ? buildEmptyCard('No reviews yet. Be the first to add one!')
              : Column(
                  children: reviews
                      .map((review) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(review.userName,
                                          style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Row(
                                        children: List.generate(5, (index) {
                                          return Icon(
                                            index < review.rating ? Icons.star : Icons.star_border,
                                            color: Colors.amber,
                                            size: 18,
                                          );
                                        }),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(review.comment),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('MMM d, yyyy').format(review.date),
                                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
          const SizedBox(height: 16),
          buildSectionHeader('Add Review', Icons.rate_review, Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setState(() {
                            _rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                  TextField(
                    controller: _reviewController,
                    decoration: const InputDecoration(
                      hintText: 'Share your experience...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        // Add your review submission logic here
                      },
                      child: const Text('Submit Review'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void shareCave() {
    // Create a more detailed share message with additional information
    final weatherInfo = weatherData != null 
        ? '\nCurrent Weather: ${weatherData!['weather'][0]['description'].toString().toCapitalized()}, ${(weatherData!['main']['temp'] as num).toStringAsFixed(1)}°C'
        : '';
    
    final conservationStatus = githubCaveData?['ConservationStatus'] != null
        ? '\nConservation Status: ${githubCaveData!['ConservationStatus']}'
        : '';
    
    final difficulty = githubCaveData?['Difficulty'] != null
        ? '\nDifficulty: ${githubCaveData!['Difficulty']}'
        : '';
    
    Share.share(
      'Check out ${widget.cave.name}!\n'
      'Located at: ${widget.cave.location.latitude}, ${widget.cave.location.longitude}\n'
      'Description: ${widget.cave.description}'
      '$weatherInfo'
      '$conservationStatus'
      '$difficulty'
      '\n\nShared via Karst App',
    );
  }
  
  // This method is now replaced by the more complete getWeatherIcon implementation above
  // and is kept for reference only
  Widget getLegacyWeatherIcon(String weatherMain) {
    return getWeatherIcon(weatherMain, context);
  }
  
  // Helper method to calculate flood risk based on weather data
  double calculateFloodRisk() {
    if (weatherData == null) return 0.0;
    
    double risk = 0.0;
    
    // Check if rain is present in current weather
    final String conditions = weatherData!['weather'][0]['main'].toString().toLowerCase();
    if (conditions.contains('rain')) {
      // Light rain: +0.2, moderate: +0.4, heavy: +0.6
      final String description = weatherData!['weather'][0]['description'].toString().toLowerCase();
      if (description.contains('light')) {
        risk += 0.2;
      } else if (description.contains('heavy')) {
        risk += 0.6;
      } else {
        risk += 0.4;
      }
    }
    
    if (conditions.contains('thunder') || conditions.contains('storm')) {
      risk += 0.3;
    }
    
    // Factor 2: Current humidity
    final double humidity = (weatherData!['main']['humidity'] as num).toDouble();
    risk += (humidity / 100) * 0.3; // Max contribution: 0.3
    
    // Factor 3: Cave-specific flood risk from GitHub data
    if (githubCaveData != null) {
      final String floodHistory = (githubCaveData?['FloodHistory'] ?? '').toString().toLowerCase();
      if (floodHistory.contains('frequent') || floodHistory.contains('high')) {
        risk += 0.3;
      } else if (floodHistory.contains('occasional') || floodHistory.contains('medium')) {
        risk += 0.2;
      } else if (floodHistory.contains('rare') || floodHistory.contains('low')) {
        risk += 0.1;
      }
    }
    
    // Ensure risk is between 0 and 1
    return risk.clamp(0.0, 1.0);
  }
  
  double calculateFloodRiskLevel() {
    if (weatherData == null) return 0;
    
    // Check if rain is present in current weather
    double risk = 0;
    final String conditions = weatherData!['weather'][0]['main'].toString().toLowerCase();
    if (conditions.contains('rain')) {
      // Light rain: +0.2, moderate: +0.4, heavy: +0.6
      final String description = weatherData!['weather'][0]['description'].toString().toLowerCase();
      if (description.contains('light')) {
        risk += 0.2;
      } else if (description.contains('heavy')) {
        risk += 0.6;
      } else {
        risk += 0.4;
      }
    }
    
    if (conditions.contains('thunder') || conditions.contains('storm')) {
      risk += 0.3;
    }
    
    // Factor in cave-specific flood risk from GitHub data
    if (githubCaveData != null) {
      final String floodHistory = (githubCaveData?['FloodRisk'] ?? '').toString().toLowerCase();
      if (floodHistory.contains('high')) {
        risk += 0.3;
      } else if (floodHistory.contains('medium')) {
        risk += 0.2;
      } else if (floodHistory.contains('low')) {
        risk += 0.1;
      }
    }
    
    return risk;
  }
    bool hasFloodRisk() {
    if (weatherData == null) return false;
    
    final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase();
    return conditions != null && (conditions.contains('rain') || conditions.contains('storm'));
  }
  
  Widget buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  // Check if precipitation data is available in the weather data
  bool hasPrecipitation() {
    if (_currentState?.weatherData == null) return false;
    return _currentState!.weatherData!.containsKey('rain') || _currentState!.weatherData!.containsKey('snow');
  }
  
  // Check if 3-hour precipitation data is available
  bool hasPrecipitation3h() {
    if (weatherData == null) return false;
    
    return (weatherData!['rain']?.containsKey('3h') ?? false) || 
           (weatherData!['snow']?.containsKey('3h') ?? false);
  }
  
  // Get 1-hour precipitation amount (rain or snow)
  String getPrecipitation1h() {
    if (weatherData == null) return '0.0';
    double precipitation = 0.0;
    
    // Check for rain data
    if (weatherData!.containsKey('rain')) {
      precipitation += (weatherData!['rain']['1h'] ?? 0.0) as double;
    }
    
    // Check for snow data
    if (weatherData!.containsKey('snow')) {
      precipitation += (weatherData!['snow']['1h'] ?? 0.0) as double;
    }
    
    return precipitation.toStringAsFixed(1);
  }
  
  // Get 3-hour precipitation amount (rain or snow)
  String getPrecipitation3h() {
    if (weatherData == null) return '0.0';
    
    double precipitation = 0.0;
    
    // Check for rain data
    if (weatherData!.containsKey('rain')) {
      precipitation += (weatherData!['rain']['3h'] ?? 0.0) as double;
    }
    
    // Check for snow data
    if (weatherData!.containsKey('snow')) {
      precipitation += (weatherData!['snow']['3h'] ?? 0.0) as double;
    }
    
    return precipitation.toStringAsFixed(1);
  }
  
  // Fix the temperature chart to safely handle numeric values
  Widget buildTemperatureChart() {
    if (forecastData == null || forecastData!.isEmpty) {
      return buildEmptyCard('No temperature data available');
    }
    
    // Add this safe conversion function to handle various data types
    double safeToDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {
          return 0.0;
        }
      }
      return 0.0;
    }
    
    // Use the safe conversion when generating chart spots
    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.1),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}°C',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= forecastData!.length + 1) return const Text('');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      index == 0 ? 'Now' : formatDate(forecastData![index - 1]['date'].toString()),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          minY: getMinTemperatureData() - 5,
          maxY: getMaxTemperatureData() + 5,
          lineBarsData: [
            // AM temperature line - using safe conversion
            LineChartBarData(
              spots: List.generate(
                forecastData!.length,
                (index) => FlSpot(
                  (index + 1).toDouble(),
                  safeToDouble(forecastData![index]['amTemp']),
                ),
              ),
              isCurved: true,
              color: Colors.lightBlue,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
            // PM temperature line - using safe conversion
            LineChartBarData(
              spots: List.generate(
                forecastData!.length,
                (index) => FlSpot(
                  (index + 1).toDouble(),
                  safeToDouble(forecastData![index]['pmTemp']),
                ),
              ),
              isCurved: true,
              color: Colors.orange,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
  
  // Also update _getMinTemperature and _getMaxTemperature methods to use the same safe conversion
  double getMinTemperature() {
    if (_currentState?.forecastData == null || _currentState!.forecastData!.isEmpty) return 0;
    
    double safeToDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {
          return 0.0;
        }
      }
      return 0.0;
    }
    
    double minTemp = double.infinity;
    for (var day in _currentState!.forecastData!) {
      final amTemp = safeToDouble(day['amTemp']);
      final pmTemp = safeToDouble(day['pmTemp']);
      if (amTemp < minTemp) minTemp = amTemp;
      if (pmTemp < minTemp) minTemp = pmTemp;
    }
    return minTemp.isFinite ? minTemp : 0;
  }
  
  // Add method for getting minimum temperature data for charts
  double getMinTemperatureData() {
    if (forecastData == null || forecastData!.isEmpty) return 0;
    
    double safeToDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {
          return 0.0;
        }
      }
      return 0.0;
    }
    
    double minTemp = double.infinity;
    for (var day in forecastData!) {
      final amTemp = safeToDouble(day['amTemp']);
      final pmTemp = safeToDouble(day['pmTemp']);
      if (amTemp < minTemp) minTemp = amTemp;
      if (pmTemp < minTemp) minTemp = pmTemp;
    }
    return minTemp.isFinite ? minTemp : 0;
  }
  
  // Add method for getting maximum temperature data for charts
  double getMaxTemperatureData() {
    if (forecastData == null || forecastData!.isEmpty) return 0;
    
    double safeToDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {
          return 0.0;
        }
      }
      return 0.0;
    }
    
    double maxTemp = double.negativeInfinity;
    for (var day in forecastData!) {
      final amTemp = safeToDouble(day['amTemp']);
      final pmTemp = safeToDouble(day['pmTemp']);
      if (amTemp > maxTemp) maxTemp = amTemp;
      if (pmTemp > maxTemp) maxTemp = pmTemp;
    }
    return maxTemp.isFinite ? maxTemp : 0;
  }
  
  double getMaxTemperature() {
    if (_currentState?.forecastData == null || _currentState!.forecastData!.isEmpty) return 0;
    
    double safeToDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (_) {
          return 0.0;
        }
      }
      return 0.0;
    }
    
    double maxTemp = double.negativeInfinity;
    for (var day in _currentState!.forecastData!) {
      final amTemp = safeToDouble(day['amTemp']);
      final pmTemp = safeToDouble(day['pmTemp']);
      if (amTemp > maxTemp) maxTemp = amTemp;
      if (pmTemp > maxTemp) maxTemp = pmTemp;
    }
    return maxTemp.isFinite ? maxTemp : 0;
  }
  
  // Add method to format date
  String formatDate(String date) {
    final DateTime parsedDate = DateTime.parse(date);
    return DateFormat('MMM d').format(parsedDate);
  }
  
  // Add method to format precipitation values
  String formatPrecipitation(double value) {
    if (value < 0.1) return '0 mm';
    if (value < 1) return '${(value * 10).round() / 10} mm';
    return '${value.round()} mm';
  }
  
  // Fixed version of precipitation chart
  Widget buildPrecipitationChart() {
    if (weatherData == null || forecastData == null || forecastData!.isEmpty) {
      return buildEmptyCard('No precipitation data available');
    }
    
    final List<BarChartGroupData> barGroups = [];
    final List<String> xLabels = ['Now'];
    
    double currentPrecip = 0.0;
    // Add current precipitation
    if (weatherData != null && weatherData!['rain'] != null) {
      currentPrecip = _parseDouble(weatherData!['rain']['1h'] ?? 0.0);
    }
    barGroups.add(createBarGroup(0, currentPrecip));
    
    // Add forecast precipitation
    for (int i = 0; i < forecastData!.length; i++) {
      final forecast = forecastData![i];
      final weather = forecast['weather'] as Map<String, dynamic>?;
      final description = weather?['description']?.toString().toLowerCase() ?? '';
      double precipValue = 0.0;
      
      if (description.contains('rain')) {
        if (description.contains('light')) {
          precipValue = 2.0;
        } else if (description.contains('heavy')) {
          precipValue = 15.0;
        } else {
          precipValue = 7.0;
        }
      }
      barGroups.add(createBarGroup(i + 1, precipValue));
      xLabels.add(DateFormat('E').format(DateTime.parse(forecast['date'])));
    }
    
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 20,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: Colors.black.withOpacity(0.8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${rod.toY.toStringAsFixed(1)} mm',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()} mm',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= xLabels.length) return const Text('');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      xLabels[index],
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.1),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }
  
  // Helper method to create bar groups
  BarChartGroupData createBarGroup(int x, double value) {
    Color barColor = Colors.blue;
    if (value > 10) {
      barColor = Colors.red;
    } else if (value > 5) barColor = Colors.orange;
    
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          color: barColor,
          width: 16,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ],
    );
  }
  
  // Fix for the weather widgets with incomplete references
  Widget buildAlertSystem() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weather Alerts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Configure alerts to receive notifications about dangerous weather conditions.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            // Alert system content here
            const SizedBox(height: 16),
            const Center(
              child: Text('Alert system content will appear here'),
            )
          ],
        ),
      ),
    );
  }
  
  // Fix for Safety Recommendations
  bool hasRainWarning0() {
    if (weatherData == null) return false;
    final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase() ?? '';
    return conditions.contains('rain') || conditions.contains('storm');
  }
  
  Widget buildSafetyRecommendations() {
    final bool hasRainWarning = hasRainWarning0();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Safety Recommendations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Based on current conditions, consider these safety precautions:',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            // Actual safety recommendations based on conditions
            Column(
              children: [
                buildSafetyItem(
                  icon: Icons.warning,
                  title: 'Monitor Weather',
                  description: 'Check forecasts before and during your visit',
                  color: Colors.amber,
                ),
                const SizedBox(height: 12),
                buildSafetyItem(
                  icon: Icons.people,
                  title: 'Buddy System',
                  description: 'Never explore alone, always use the buddy system',
                  color: Colors.blue,
                ),
                if (hasRainWarning) ...[
                  const SizedBox(height: 12),
                  buildSafetyItem(
                    icon: Icons.water_drop,
                    title: 'Flash Flood Risk',
                    description: 'Avoid lower passages and have an evacuation plan',
                    color: Colors.red,
                  ),
                ],
                const SizedBox(height: 12),
                buildSafetyItem(
                  icon: Icons.battery_full,
                  title: 'Extra Lighting',
                  description: 'Bring backup lighting and batteries',
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Fix for Emergency Info
  Widget buildEmergencyInfo() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emergency, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Emergency Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Keep this information handy in case of emergency:',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            // Emergency info content
            const SizedBox(height: 16),
            Column(
              children: [
                buildEmergencyContact(
                  title: 'Emergency Services',
                  contact: '911',
                  icon: Icons.emergency,
                ),
                const SizedBox(height: 12),
                buildEmergencyContact(
                  title: 'Cave Rescue',
                  contact: '1-800-555-CAVE',
                  icon: Icons.help_outline,
                ),
                const SizedBox(height: 12),
                buildEmergencyContact(
                  title: 'Park Ranger',
                  contact: '1-800-555-PARK',
                  icon: Icons.park,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'In case of rising water, move to higher ground immediately and wait for rescue.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Helper for emergency contacts
  Widget buildEmergencyContact({
    required String title,
    required String contact,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.red, size: 20),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        Text(
          contact,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  // Helper method for safety item
  Widget buildSafetyItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Method for launching URLs (permit applications, etc.)
Future<void> launchURL(String url) async {
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url));
  } else {
    throw 'Could not launch $url';
  }
}
Widget buildRoutesTab() {
  final primaryColor = Theme.of(context).colorScheme.primary;
  
  if (isLoading) {
    return const Center(child: CircularProgressIndicator());
  }
  
  if (hasError || githubCaveData == null) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.route_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Unable to load route data',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
  
  // Check if there are routes in the GitHub data
  final hasRoutes = githubCaveData!.containsKey('Routes') && 
                   githubCaveData!['Routes'].toString().trim().isNotEmpty;
  
  // Extract multiple routes if they exist (comma-separated)
  List<String> routeNames = [];
  if (hasRoutes) {
    routeNames = githubCaveData!['Routes'].toString().split(',').map((e) => e.trim()).toList();
  } else if (githubCaveData!.containsKey('RouteName') && 
             githubCaveData!['RouteName'].toString().trim().isNotEmpty) {
    routeNames = [githubCaveData!['RouteName']];
  } else {
    routeNames = ['Main Route']; // Default route
  }
  
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current weather alert at the top for safety
        if (hasRainWarning0()) buildCriticalRainWarning(),
        
        const SizedBox(height: 16),
        
        // Route selector for multi-route caves
        if (routeNames.length > 1) ...[
          Text(
            'Available Routes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: routeNames.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: ChoiceChip(
                    label: Text(routeNames[index]),
                    selected: index == 0, // First route selected by default
                    onSelected: (selected) {
                      // Logic to switch between routes
                    },
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // Interactive route card with expandable sections
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route header with difficulty badge
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            githubCaveData!['RouteName'] ?? routeNames.first,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                githubCaveData!['RouteLength'] ?? 'Unknown length',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 16),
                              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                githubCaveData!['RouteDuration'] ?? 'Varies',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getDifficultyColor(githubCaveData?['RouteDifficulty'] ?? githubCaveData?['DifficultyLevel']),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        githubCaveData?['RouteDifficulty'] ?? githubCaveData?['DifficultyLevel'] ?? 'Moderate',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // NEW: Passage Dimensions section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSectionTitle('Passage Dimensions'),
                    const SizedBox(height: 12),
                    buildPassageDimensionsInfo(),
                    
                    const Divider(height: 32),
                    
                    // NEW: Technical Obstacles section
                    buildSectionTitle('Technical Obstacles'),
                    const SizedBox(height: 12),
                    buildTechnicalObstacles(),
                    
                    const Divider(height: 32),
                    
                    // NEW: Anchor Points section for SRT routes
                    if (githubCaveData!['SRT']?.toString().toLowerCase() == 'yes') ...[
                      buildSectionTitle('Anchor Points'),
                      const SizedBox(height: 12),
                      buildAnchorPointsList(),
                      const Divider(height: 32),
                    ],
                    
                    // NEW: Route Variations section
                    buildSectionTitle('Route Variations'),
                    const SizedBox(height: 12),
                    buildRouteVariations(),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // NEW: Additional route-specific data
        const SizedBox(height: 24),
        buildRouteDataSection(),
      ],
    ),
  );
}

// Helper widget for section titles
Widget buildSectionTitle(String title) {
  return Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Container(
          height: 1,
          color: Colors.grey.withOpacity(0.3),
        ),
      ),
    ],
  );
}

// Passage dimensions visualization
Widget buildPassageDimensionsInfo() {
  final passageData = githubCaveData?['PassageDimensions']?.toString() ?? '';
  
  if (passageData.isEmpty) {
    return buildInfoBox(
      icon: Icons.straighten,
      title: 'Passage Size',
      content: githubCaveData?['PassageSize'] ?? 'No dimension data available',
      color: Colors.blue,
    );
  }

  // Parse dimension data (format: "entrance:3x2,main passage:5x3,crawl:0.6x0.8")
  final dimensions = <Map<String, dynamic>>[];
  final dimensionsList = passageData.split(',');
  
  for (final dimension in dimensionsList) {
    final parts = dimension.trim().split(':');
    if (parts.length == 2 && parts[1].contains('x')) {
      final name = parts[0].trim();
      final sizeParts = parts[1].trim().split('x');
      if (sizeParts.length == 2) {
        try {
          final width = double.parse(sizeParts[0]);
          final height = double.parse(sizeParts[1]);
          dimensions.add({
            'name': name,
            'width': width,
            'height': height,
          });
        } catch (e) {
          // Skip invalid dimensions
        }
      }
    }
  }

  if (dimensions.isEmpty) {
    return buildInfoBox(
      icon: Icons.straighten,
      title: 'Passage Size',
      content: githubCaveData?['PassageSize'] ?? 'Variable',
      color: Colors.blue,
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: dimensions.map((dimension) {
      final name = dimension['name'] as String;
      final width = dimension['width'] as double;
      final height = dimension['height'] as double;
      final isTight = width < 1.0 || height < 1.0;
      final sizeDescription = '${width.toString()}m × ${height.toString()}m';
      final sizeCategory = isTight 
        ? 'Tight squeeze' 
        : (width > 3.0 && height > 2.0) 
            ? 'Large passage' 
            : 'Average passage';
        
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isTight ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isTight ? Icons.compress : Icons.expand,
                color: isTight ? Colors.orange : Colors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    sizeDescription,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    sizeCategory,
                    style: TextStyle(
                      color: isTight ? Colors.orange : Colors.blue,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

// Technical obstacles section
Widget buildTechnicalObstacles() {
  final obstacles = githubCaveData?['TechnicalObstacles']?.toString() ?? '';
  
  if (obstacles.isEmpty) {
    return buildInfoBox(
      icon: Icons.warning,
      title: 'No Technical Obstacles',
      content: 'No specific technical obstacles are documented for this route',
      color: Colors.green,
    );
  }
  
  final obstacleList = obstacles.split(',');
  
  return Column(
    children: obstacleList.map((obstacle) {
      final trimmed = obstacle.trim();
      IconData icon;
      Color color;
      
      // Determine icon and color based on obstacle type
      if (trimmed.toLowerCase().contains('pitch') || 
          trimmed.toLowerCase().contains('drop') ||
          trimmed.toLowerCase().contains('vertical')) {
        icon = Icons.vertical_align_bottom;
        color = Colors.red;
      } else if (trimmed.toLowerCase().contains('crawl') ||
                 trimmed.toLowerCase().contains('squeeze')) {
        icon = Icons.compress;
        color = Colors.orange;
      } else if (trimmed.toLowerCase().contains('water') || 
                 trimmed.toLowerCase().contains('sump')) {
        icon = Icons.water;
        color = Colors.blue;
      } else if (trimmed.toLowerCase().contains('climb')) {
        icon = Icons.trending_up;
        color = Colors.purple;
      } else {
        icon = Icons.warning;
        color = Colors.amber;
      }
      
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          trimmed,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        dense: true,
      );
    }).toList(),
  );
}

// Anchor points for SRT sections
Widget buildAnchorPointsList() {
  final anchors = githubCaveData?['AnchorPoints']?.toString() ?? '';
  
  if (anchors.isEmpty) {
    return buildInfoBox(
      icon: Icons.help_outline,
      title: 'SRT Information',
      content: 'This route requires SRT techniques, but specific anchor information is not available',
      color: Colors.orange,
    );
  }
  
  final anchorList = anchors.split(',');
  
  return Column(
    children: anchorList.map((anchor) {
      final trimmed = anchor.trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.anchor, color: Colors.purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                trimmed,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

// Route variations
Widget buildRouteVariations() {
  final variations = githubCaveData?['RouteVariations']?.toString() ?? '';
  
  if (variations.isEmpty) {
    return buildInfoBox(
      icon: Icons.alt_route,
      title: 'Standard Route',
      content: 'No alternative routes or variations documented',
      color: Colors.blue,
    );
  }
  
  final variationList = variations.split(';');
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: variationList.map((variation) {
      final parts = variation.split(':');
      if (parts.length < 2) return const SizedBox.shrink();
      
      final name = parts[0].trim();
      final description = parts[1].trim();
      
      return Card(
        elevation: 0,
        color: Colors.grey.shade50,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route, color: Colors.purple, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

// Additional route data section
Widget buildRouteDataSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // NEW: Route Classification information
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.category, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  const Text(
                    'Route Classification',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              buildClassificationItem(
                title: 'Technical Grade',
                value: githubCaveData?['TechnicalGrade'] ?? 'Not specified',
                description: 'Difficulty of technical challenges',
              ),
              const SizedBox(height: 12),
              buildClassificationItem(
                title: 'Commitment Grade',
                value: githubCaveData?['CommitmentGrade'] ?? 'Not specified',
                description: 'Required time and physical effort',
              ),
              const SizedBox(height: 12),
              buildClassificationItem(
                title: 'Water Rating',
                value: githubCaveData?['WaterRating'] ?? 'Not specified',
                description: 'Presence and impact of water',
              ),
            ],
          ),
        ),
      ),
      
      const SizedBox(height: 24),
      
      // NEW: First Aid & Emergency Info
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.emergency, color: Colors.red),
                  SizedBox(width: 12),
                  Text(
                    'Emergency Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                githubCaveData?['EmergencyInfo'] ?? 
                'In case of emergency, exit the cave if possible and call local cave rescue. Mark your route and inform rescuers about the condition of the injured person.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
              if (githubCaveData?['EmergencyContacts'] != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Emergency Contacts:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  githubCaveData!['EmergencyContacts'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

// Helper for classification items
Widget buildClassificationItem({
  required String title,
  required String value,
  required String description,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ],
  );
}

// Generic info box for when no specific data is available
Widget buildInfoBox({
  required IconData icon,
  required String title,
  required String content,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
Widget build(BuildContext context) {
  final String grade = widget.cave.csvData['grade'] ?? 'N/A';
  final primaryGrade = grade.isNotEmpty ? grade[0] : 'N/A';
  final secondaryGrade = grade.length > 1 ? grade[1] : '';
  final gradeColor = getGradeColor(primaryGrade);
  
  return DefaultTabController(
    length: 7,
    child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(widget.cave.name),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: gradeColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: gradeColor),
              ),
              child: Text(
                grade,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: gradeColor,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
            onPressed: toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: shareCave,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Technical'),
            Tab(text: 'Routes'),
            Tab(text: 'Weather'),
            Tab(text: 'Location'),  // Add new tab
            Tab(text: 'Community'),
            Tab(text: '3D Model'),  // Add new tab
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          buildOverviewTab(),
          buildTechnicalTab(),
          buildRoutesTab(),
          buildWeatherTab(),
          buildLocationTab(), // Add new tab view
          buildCommunityTab(),
          build3DModelTab(),  // Add new tab view
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: toggleMonitoring,
        backgroundColor: _isMonitored ? Theme.of(context).colorScheme.primary : Colors.grey,
        child: Icon(_isMonitored ? Icons.notifications_active : Icons.notifications_off),
      ),
    ),
  );
}

// Add this method to get grade colors matching the map screen
Color getGradeColor(String grade) {
  switch (grade) {
    case '1': return Colors.green;
    case '2': return Colors.lightGreen;
    case '3': return Colors.amber;
    case '4': return Colors.orange;
    case '5': return Colors.deepOrange;
    case '6': return Colors.red;
    default: return Colors.grey;
  }
}

// Define the WeatherAlert class
class WeatherAlert {
  final String id;
  final String title;
  final String description;
  final String severity;
  final DateTime startTime;
  final DateTime endTime;
  final List<String> areas;
  
  WeatherAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.startTime,
    required this.endTime,
    required this.areas,
  });
}

// Weather alert handling service
class WeatherAlertService {
  Future<List<WeatherAlert>> getActiveAlerts(LatLng location) async {
    // Implementation to fetch weather alerts
    return [];
  }
  
  bool shouldShowAlert(WeatherAlert alert, Cave cave) {
    // Logic to determine if alert is relevant
    return true;
  }
}

// Define the WeatherDataPoint class
class WeatherDataPoint {
  final DateTime date;
  final double temperature;
  final double humidity;
  final String weatherType;
  final double precipitation;
  
  WeatherDataPoint({
    required this.date,
    required this.temperature,
    required this.humidity,
    required this.weatherType,
    required this.precipitation,
  });
}

// Missing historical weather data handling
class HistoricalWeatherService {
  Future<List<WeatherDataPoint>> getHistoricalData(
    LatLng location,
    DateTime startDate,
    DateTime endDate
  ) async {
    // Implementation
    return [];
  }
}

Widget buildEnhancedTechnicalInfo() {
  final githubCaveData = _currentState?.githubCaveData;

  // Group the technical data into categories for better organization
  final Map<String, List<Map<String, dynamic>>> categoryGroups = {
    'Geology': [
      {'label': 'Rock Type', 'field': 'RockType', 'icon': Icons.landscape},
      {'label': 'Formation Type', 'field': 'FormationType', 'icon': Icons.category},
      {'label': 'Age', 'field': 'GeologicalAge', 'icon': Icons.history},
    ],
    'Environment': [
      {'label': 'Temperature Range', 'field': 'TemperatureRange', 'icon': Icons.thermostat},
      {'label': 'Humidity', 'field': 'AverageHumidity', 'icon': Icons.water_drop},
      {'label': 'Air Quality', 'field': 'AirQuality', 'icon': Icons.air},
    ],
    'Water Conditions': [
      {'label': 'Water Presence', 'field': 'WetCave', 'icon': Icons.water},
      {'label': 'Flood Risk', 'field': 'FloodRisk', 'icon': Icons.warning, 'colorCoded': true},
      {'label': 'Water Sources', 'field': 'WaterSources', 'icon': Icons.waves},
    ],
    'Access & Preservation': [
      {'label': 'Access Difficulty', 'field': 'AccessLevel', 'icon': Icons.hiking},
      {'label': 'Permit Required', 'field': 'AccessPermitRequired', 'icon': Icons.badge},
      {'label': 'Conservation Status', 'field': 'ConservationStatus', 'icon': Icons.eco},
      {'label': 'Visitor Capacity', 'field': 'VisitorCapacity', 'icon': Icons.people},
    ],
    'Equipment & Safety': [
      {'label': 'Required Gear', 'field': 'Gear', 'icon': Icons.backpack},
      {'label': 'Warnings', 'field': 'Warnings', 'icon': Icons.warning},
      {'label': 'Emergency Exits', 'field': 'EmergencyExits', 'icon': Icons.exit_to_app},
      {'label': 'SRT Required', 'field': 'SRT', 'icon': Icons.architecture},
    ],
  };

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: categoryGroups.entries.map((category) {
      // Check if category has any non-empty values
      bool hasData = category.value.any((field) {
        final value = githubCaveData?[field['field']]?.toString() ?? '';
        return value.isNotEmpty && value != 'Not specified' && value != 'Unknown';
      });
      
      if (!hasData) return const SizedBox.shrink();
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    getCategoryIcon(category.key),
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  category.key,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: category.value.map((field) {
                  final value = githubCaveData?[field['field']]?.toString() ?? 'Not specified';
                  if (value.isEmpty || value == 'Not specified' || value == 'Unknown') {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      ListTile(
                        leading: Icon(field['icon'] as IconData),
                        title: Text(field['label'] as String),
                        subtitle: Text(value),
                      ),
                      const Divider(),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }).toList(),
  );
}

// Helper method to get icon for category
IconData getCategoryIcon(String category) {
  switch (category) {
    case 'Geology':
      return Icons.landscape;
    case 'Environment':
      return Icons.thermostat;
    case 'Water Conditions':
      return Icons.water;
    case 'Access & Preservation':
      return Icons.shield;
    case 'Equipment & Safety':
      return Icons.backpack;
    default:
      return Icons.info_outline;
  }
}

// Helper method to get color for certain values
Color getValueColor(String value) {
  final String lowerValue = value.toLowerCase();
  
  if (lowerValue.contains('high') || lowerValue.contains('danger')) {
    return Colors.red;
  } else if (lowerValue.contains('medium') || lowerValue.contains('moderate') || 
            lowerValue.contains('caution')) {
    return Colors.orange;
  } else if (lowerValue.contains('low') || lowerValue.contains('safe')) {
    return Colors.green;
  } else if (lowerValue.contains('protected') || lowerValue.contains('conservation')) {
    return Colors.green.shade700;
  } else if (lowerValue.contains('endangered')) {
    return Colors.red.shade700;
  }
  
  return Colors.grey[800]!;
}// Helper method to get color for certain values
Color getValueColor(String value) {
  final String lowerValue = value.toLowerCase();
  
  if (lowerValue.contains('high') || lowerValue.contains('danger')) {
    return Colors.red;
  } else if (lowerValue.contains('medium') || lowerValue.contains('moderate') || 
            lowerValue.contains('caution')) {
    return Colors.orange;
  } else if (lowerValue.contains('low') || lowerValue.contains('safe')) {
    return Colors.green;
  } else if (lowerValue.contains('protected') || lowerValue.contains('conservation')) {
    return Colors.green.shade700;
  } else if (lowerValue.contains('endangered')) {
    return Colors.red.shade700;
  }
  
  return Colors.grey[800]!;
}

Widget buildOverviewSummaryCard() {
  if (_currentState?.githubCaveData == null) return const SizedBox.shrink();
  
  // Key summary fields to display in overview
  final summaryFields = [
    { 
      'title': 'Type', 
      'icon': Icons.landscape, 
      'value': _currentState?.githubCaveData?['Type'] ?? 'Unknown'
    },
    { 
      'title': 'Length', 
      'icon': Icons.straighten, 
      'value': _currentState?.githubCaveData?['Length'] ?? 'Unknown'
    },
    { 
      'title': 'Depth', 
      'icon': Icons.height, 
      'value': _currentState?.githubCaveData?['Depth'] ?? 'Unknown'
    },
    { 
      'title': 'Formation', 
      'icon': Icons.category, 
      'value': _currentState?.githubCaveData?['FormationType'] ?? 'Unknown'
    },
    { 
      'title': 'Water', 
      'icon': Icons.water, 
      'value': _currentState?.githubCaveData?['WetCave']?.toString().toLowerCase() == 'yes' ? 'Present' : 'Dry'
    },
    { 
      'title': 'Status', 
      'icon': Icons.eco, 
      'value': _currentState?.githubCaveData?['ConservationStatus'] ?? 'Unknown'
    },
  ];
  
  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key stats in a more compact row
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: summaryFields.map((field) {
              final value = field['value'] as String;
              final bool isFloodRisk = field['title'] == 'Flood Risk';
              final Color valueColor = isFloodRisk ? getFloodRiskColor(value) : Colors.black;
              
              return Container(
                width: 95,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(field['icon'] as IconData, color: Colors.blue.shade700, size: 18),
                    const SizedBox(height: 3),
                    Text(
                      field['title'] as String,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.length > 15 ? '${value.substring(0, 15)}...' : value,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: valueColor,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          
          // Add description below the compact stats if available
          if (_currentState?.githubCaveData?['LongDescription'] != null && 
              (_currentState!.githubCaveData!['LongDescription'].toString().isNotEmpty)) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Description',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _currentState!.githubCaveData!['LongDescription'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// NEW FEATURE: Cave-specific weather impact card
Widget buildCaveImpactCard() {
  // Calculate flood risk based on weather and cave data
  final floodRisk = (_currentState?._calculateFloodRiskLevel() ?? 0) > 0 
      ? _currentState?._calculateFloodRiskLevel() ?? 0 
      : WeatherUtils.calculateRainIntensity(_currentState?.weatherData);
      
  final watershedSaturation = WeatherUtils.calculateWatershedSaturation(_currentState?.weatherData, _currentState?.githubCaveData) * 100; // Convert to percentage
  final isRaining = _currentState?._hasRainWarning() ?? false;
  final rainIntensity = WeatherUtils.calculateRainIntensity(_currentState?.weatherData);
  final runoffTime = WeatherUtils.calculateRunoffTime(rainIntensity);
  
  // Determine if conditions are good for caving 
  final bool isSafeToCave = floodRisk < 0.5;
  final String safetySuggestion = isSafeToCave ? 
      'Current conditions appear suitable for caving' : 
      'Consider postponing your visit due to potentially unsafe conditions';
      
  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSafeToCave ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSafeToCave ? Icons.check_circle : Icons.warning,
                color: isSafeToCave ? Colors.green : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cave Condition Assessment',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSafeToCave ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Impact details
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                safetySuggestion,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSafeToCave ? Colors.green.shade800 : Colors.orange.shade800,
                ),
              ),
              const SizedBox(height: 20),
              
              // Watershed saturation indicator
              Text(
                'Watershed Saturation',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: watershedSaturation / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  watershedSaturation > 70 ? Colors.red :
                  watershedSaturation > 40 ? Colors.orange : Colors.green
                ),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Low',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    'Moderate',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    'High',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.water, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Text(
                    'Current saturation: ${watershedSaturation.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              
              // Estimated runoff time if it's rainy
              if (isRaining) ...[
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.timer, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estimated Runoff Time',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            runoffTime,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Time for water levels to recede after precipitation stops',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              
              // Cave-specific warning based on type
              if (_currentState?.githubCaveData != null && 
                  _currentState!.githubCaveData!.containsKey('Type') && 
                  _currentState!.githubCaveData!['Type'].toString().toLowerCase().contains('stream')) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Stream Cave Alert',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This is a stream cave and may experience rapid water level changes during and after precipitation.',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Cave flood risk from GitHub data if available
              if (_currentState?.githubCaveData != null && _currentState!.githubCaveData!.containsKey('FloodRisk')) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: getFloodRiskColor(_currentState?.githubCaveData?['FloodRisk'] ?? 'Unknown').withOpacity(0.1),
                        border: Border.all(
                          color: getFloodRiskColor(_currentState?.githubCaveData?['FloodRisk'] ?? 'Unknown'),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.warning_amber, 
                        color: getFloodRiskColor(_currentState?.githubCaveData?['FloodRisk'] ?? 'Unknown'),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Documented Flood Risk',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          _currentState?.githubCaveData!['FloodRisk'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: getFloodRiskColor(_currentState?.githubCaveData?['FloodRisk'] ?? 'Unknown'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
Widget buildWeatherDetailItem({
  required IconData icon,
Widget Function({
  required IconData icon,
  required String label,
  required String value,
}) buildWeatherDetailItem {child: Column(
  return Expanded(gnment: CrossAxisAlignment.start,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [n: [
        Row(Icon(icon, size: 16, color: Colors.grey[600]),
          children: [edBox(width: 4),
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(le: TextStyle(
              label,Size: 12,
              style: TextStyle(rey[600],
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],t SizedBox(height: 4),
        ),xt(
        const SizedBox(height: 4),
        Text(le: const TextStyle(
          value,Size: 15,
          style: const TextStyle(t.bold,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}// Add these helper methods for the enhanced weather view
Widget getLargeWeatherIcon(String weatherMain) {
  IconData iconData;
  switch (weatherMain.toLowerCase()) {
    case 'clear':
      iconData = Icons.wb_sunny;
      break;
    case 'clouds':
      iconData = Icons.cloud;
      break;
    case 'rain':
      iconData = Icons.grain;
      break;
    case 'drizzle':
      iconData = Icons.water_drop;
      break;
    case 'thunderstorm':
      iconData = Icons.flash_on;
      break;
    case 'snow':
      iconData = Icons.ac_unit;
      break;
    case 'mist':
    case 'fog':
      iconData = Icons.cloud_queue;
      break;
    default:
      iconData = Icons.wb_cloudy;
  }
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: getWeatherBackgroundColor(weatherMain).withOpacity(0.1),
      shape: BoxShape.circle,
    ),
    child: Icon(
      iconData,
      color: getWeatherBackgroundColor(weatherMain),
      size: 40,
    ),
  );
}

Color getWeatherBackgroundColor(String weatherMain) {
  switch (weatherMain.toLowerCase()) {
    case 'clear':
      return Colors.amber;
    case 'clouds':
      return Colors.blueGrey;
    case 'rain':
    case 'drizzle':
      return Colors.blue;
    case 'thunderstorm':
      return Colors.deepPurple;
    case 'snow':
      return Colors.lightBlue;
    default:
      return Colors.grey;
  }
}

double calculateWeatherSafetyIndex() {
  if (_currentState?.weatherData == null) return 0.5;
  
  double index = 0.0;
  
  // Local helper to check precipitation
  bool hasPrecipitation() {
    return _currentState!.weatherData!.containsKey('rain') || _currentState!.weatherData!.containsKey('snow');
  }
  
  // Check for precipitation
  if (hasPrecipitation()) {
    final String description = _currentState!.weatherData!['weather'][0]['description'].toString().toLowerCase();
    if (description.contains('heavy') || description.contains('extreme')) {
      index += 0.6;
    } else if (description.contains('light')) {
      index += 0.2;
    } else {
      index += 0.4;
    }
  }
  
  // Check for thunderstorms
  if (_currentState!.weatherData!['weather'][0]['main'].toString().toLowerCase().contains('thunder')) {
    index += 0.3;
  }
  
  // Check for cave-specific flood risk
  if (_currentState?.githubCaveData != null && _currentState!.githubCaveData!.containsKey('FloodRisk')) {
    final floodRisk = _currentState!.githubCaveData!['FloodRisk'].toString().toLowerCase();
    if (floodRisk.contains('high')) {
      index += 0.3;
    } else if (floodRisk.contains('medium')) {
      index += 0.2;
    } else if (floodRisk.contains('low')) {
      index += 0.1;
    }
  }
  
  return index.clamp(0.0, 1.0);
}

Color getSafetyColor(double safetyIndex) {
  if (safetyIndex >= 0.7) {
    return Colors.red;
  } else if (safetyIndex >= 0.4) {
    return Colors.orange;
  } else {
    return Colors.green;
  }
}

String getSafetyText(double safetyIndex) {
  if (safetyIndex >= 0.7) {
    return 'Dangerous';
  } else if (safetyIndex >= 0.4) {
    return 'Caution';
  } else {
    return 'Safe';
  }
}

Color getFloodRiskColor(String riskLevel) {
  final String risk = riskLevel.toLowerCase();
  if (risk.contains('high')) {
    return Colors.red;
  } else if (risk.contains('medium') || risk.contains('moderate')) {
    return Colors.orange;
  } else if (risk.contains('low')) {
    return Colors.green;
  }
  return Colors.grey;
}

Widget getWeatherIcon(String weatherMain, BuildContext context) {
  IconData iconData;
  switch (weatherMain.toLowerCase()) {
    case 'clear':
      iconData = Icons.wb_sunny;
      break;
    case 'clouds':
      iconData = Icons.cloud;
      break;
    case 'rain':
      iconData = Icons.grain;
      break;
    case 'drizzle':
      iconData = Icons.water_drop;
      break;
    case 'thunderstorm':
      iconData = Icons.flash_on;
      break;
    case 'snow':
      iconData = Icons.ac_unit;
      break;
    case 'mist':
    case 'fog':
      iconData = Icons.cloud_queue;
      break;
    default:
      iconData = Icons.wb_cloudy;
  }
  return Icon(iconData, color: Colors.blue, size: 40);
}

Widget buildWeatherAlertSettings() {
  return Card(
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.blue),
              const SizedBox(width: 12),
              const Text(
                'Weather Alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: _currentState?._weatherAlertsEnabled ?? false,
                onChanged: (value) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('weather_alerts_enabled', value);
                  _currentState?.setState(() {
                    _currentState!._weatherAlertsEnabled = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 12),
          Text(
            calculateCurrentAirflow() < 0 ? 'Currently: Inward Airflow' : 'Currently: Outward Airflow',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            calculateCurrentAirflow() < 0 
              ? 'Cold air entering the cave system'
              : 'Warm air exiting the cave system',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    ),
  );
}

List<FlSpot> getPredictedAirflowData() {
  // Generate 24-hour airflow prediction
  final currentPressure = _currentState?.weatherData?['main']?['pressure'] ?? 1013.25;
  final currentTemp = _currentState?.weatherData?['main']?['temp'] ?? 15.0;
  final currentTime = DateTime.now();
  
  // Simplified airflow model based on outside temperature and pressure changes
  return List.generate(24, (index) {
    // Model pressure changes throughout the day
    final hourOfDay = (currentTime.hour + index) % 24;
    
    // Pressure typically has a semidiurnal pattern with peaks around 10am and 10pm
    final pressureVariation = 2 * sin(pi * (hourOfDay - 4) / 12);
    
    // Temperature changes throughout the day affect the airflow direction
    final tempFactor = hourOfDay >= 8 && hourOfDay <= 18 ? 1.2 : -0.8;
    
    // The actual airflow calculation (simplified model)
    double airflow = pressureVariation * tempFactor;
    
    // Cave characteristics affect airflow intensity
    if (_currentState?.githubCaveData != null && 
        _currentState!.githubCaveData!['Type']?.toString().toLowerCase().contains('vertical') == true) {
      airflow *= 1.5; // Vertical caves often have stronger chimney effect
    }
    
    return FlSpot(index.toDouble(), airflow);
  });
}

double calculateCurrentAirflow() {
  // Simplified calculation for current airflow direction
  if (_currentState?.weatherData == null) return 0.0;
  
  final pressure = _currentState!.weatherData!['main']?['pressure'] ?? 1013.25;
  final temp = _currentState!.weatherData!['main']?['temp'] ?? 15.0;
  final hour = DateTime.now().hour;
  
  // Basic model: positive values = outflow, negative values = inflow
  double airflow = 0.0;
  
  // Temperature differential drives airflow
  if (temp < 10) {
    airflow -= 1.5; // Cold outside air tends to sink into cave
  } else if (temp > 25) {
    airflow += 1.5; // Hot outside air creates updraft from cave
  }
  
  // Pressure changes also affect airflow
  if (pressure < 1010) {
    airflow += 0.8; // Low pressure tends to draw air out
  } else if (pressure > 1020) {
    airflow -= 0.8; // High pressure tends to push air in
  }
  
  // Time of day effects (simplified)
  if (hour >= 10 && hour <= 16) {
    airflow += 0.5; // Daytime heating typically increases outflow
  } else if (hour >= 0 && hour <= 6) {
    airflow -= 0.5; // Night cooling typically increases inflow
  }
  
  return airflow;
}

String getAirflowDescription(double value) {
  if (value > 2) return 'Strong outflow';
  if (value > 1) return 'Moderate outflow';
  if (value > 0.3) return 'Slight outflow';
  if (value > -0.3) return 'Minimal airflow';
  if (value > -1) return 'Slight inflow';
  if (value > -2) return 'Moderate inflow';
  return 'Strong inflow';
}

Widget buildAirflowExplanation() {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.purple.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cave Breathing Explained:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Cave breathing (or "barometric wind") occurs when pressure differences between the cave and outside atmosphere cause air to flow in or out of the cave.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Safety note: Strong airflow can indicate multiple entrances and potentially faster flooding in wet conditions.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.purple[700],
          ),
        ),
      ],
    ),
  );
}

String getAirflowIntensity(double value) {
  if (value > 0.7) return 'Strong';
  if (value > 0.3) return 'Moderate';
  return 'Gentle';
}

Color getSurveyGradeColor(String grade) {
  final gradeLower = grade.toLowerCase();
  if (gradeLower.contains('bcra 5') || gradeLower.contains('uis 5')) {
    return Colors.green;
  } else if (gradeLower.contains('bcra 4') || gradeLower.contains('uis 4')) {
    return Colors.blue;
  } else if (gradeLower.contains('bcra 3') || gradeLower.contains('uis 3')) {
    return Colors.amber;
  } else if (gradeLower.contains('bcra 2') || gradeLower.contains('uis 2')) {
    return Colors.orange;
  } else if (gradeLower.contains('bcra 1') || gradeLower.contains('uis 1')) {
    return Colors.red;
  }
  return Colors.grey;
}

String getSurveyGradeDescription(String grade) {
  final gradeLower = grade.toLowerCase();
  if (gradeLower.contains('bcra 5') || gradeLower.contains('uis 5')) {
    return 'Professional-grade survey with high precision instruments';
  } else if (gradeLower.contains('bcra 4') || gradeLower.contains('uis 4')) {
    return 'Accurate survey with calibrated instruments';
  } else if (gradeLower.contains('bcra 3') || gradeLower.contains('uis 3')) {
    return 'Standard grade survey with decent accuracy';
  } else if (gradeLower.contains('bcra 2') || gradeLower.contains('uis 2')) {
    return 'Basic survey with some measurements';
  } else if (gradeLower.contains('bcra 1') || gradeLower.contains('uis 1')) {
    return 'Sketch survey with minimal measurements';
  }
  return 'Survey grade information unavailable';
}

Widget buildSurveyDetailItem({
  required IconData icon,
  required String label,
  required String value,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

Widget buildTemperatureGradientSection() {
  if (githubCaveData == null ||
      !githubCaveData!.containsKey('TemperatureGradient') ||
      githubCaveData!['TemperatureGradient'].toString().isEmpty) {
    return const SizedBox.shrink();
  }

  final gradientData = <String, double>{};
  final dataPoints = githubCaveData!['TemperatureGradient'].toString().split(',');
  
  for (final point in dataPoints) {
    final parts = point.trim().split(':');
    if (parts.length == 2) {
      try {
        gradientData[parts[0]] = double.parse(parts[1]);
      } catch (e) {
        // Skip invalid data points
      }
    }
  }

  if (gradientData.isEmpty) return const SizedBox.shrink();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader('Temperature Gradient', Icons.thermostat, Colors.orange),
      const SizedBox(height: 16),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Temperature varies throughout the cave:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 100,
                child: Row(
                  children: gradientData.entries.map((entry) {
                    final location = entry.key;
                    final temperature = entry.value;
                    return Expanded(
                      child: Column(
                        children: [
                          Text(
                            location.capitalize(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  getTemperatureColor(temperature).withOpacity(0.6),
                                  getTemperatureColor(temperature),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${temperature.toStringAsFixed(1)}°C',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
Color getTemperatureColor(double temperature) {
  if (temperature <= 5) return Colors.blue.shade700;
  if (temperature <= 10) return Colors.blue.shade400;
  if (temperature <= 15) return Colors.green.shade600;
  if (temperature <= 20) return Colors.amber.shade600;
  return Colors.red.shade600;
}

Widget buildPassageDimensions() {
  if (githubCaveData == null ||
      !githubCaveData!.containsKey('PassageDimensions') ||
      githubCaveData!['PassageDimensions'].toString().isEmpty) {
    return const SizedBox.shrink();
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionHeader('Passage Dimensions', Icons.dashboard, Colors.indigo),
      const SizedBox(height: 16),
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Major passage sizes throughout the cave:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
              Builder(builder: (context) {
                final dimensions = <Map<String, dynamic>>[];
                final dimensionsList = githubCaveData!['PassageDimensions']
                    .toString()
                    .split(',');

                for (final dimension in dimensionsList) {
                  final parts = dimension.trim().split(':');
                  if (parts.length == 2 && parts[1].contains('x')) {
                    final name = parts[0].trim();
                    final sizeParts = parts[1].trim().split('x');
                    if (sizeParts.length == 2) {
                      try {
                        final width = double.parse(sizeParts[0]);
                        final height = double.parse(sizeParts[1]);
                        dimensions.add({
                          'name': name,
                          'width': width,
                          'height': height,
                        });
                      } catch (e) {
                        // Skip invalid dimensions
                      }
                    }
                  }
                }

                if (dimensions.isEmpty) {
                  return Text(
                    'No dimension data available',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  );
                }

                return ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: dimensions.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final dimension = dimensions[index];
                    final name = dimension['name'] as String;
                    final width = dimension['width'] as double;
                    final height = dimension['height'] as double;
                    final isTight = width < 1.0 || height < 1.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: CustomPaint(
                              painter: PassagePainter(
                                width: width,
                                height: height,
                                isTight: isTight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.capitalize(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Width: ${width}m × Height: ${height}m',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (isTight) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Squeeze / Crawl',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),
    ],
  );
}
// Passage Visualization Painter
class PassagePainter extends CustomPainter {
  final double width;
  final double height;
  final bool isTight;

  PassagePainter({
    required this.width,
    required this.height,
    required this.isTight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxDimension = max(width, height);
    final scale = (size.width * 0.8) / maxDimension;
    final scaledWidth = width * scale;
    final scaledHeight = height * scale;
    final xOffset = (size.width - scaledWidth) / 2;
    final yOffset = (size.height - scaledHeight) / 2;

    final rect = Rect.fromLTWH(
      xOffset,
      yOffset,
      scaledWidth,
      scaledHeight,
    );

    final paint = Paint()
      ..color = isTight ? Colors.orange : Colors.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final ratio = width / height;
    if (ratio > 0.7 && ratio < 1.3) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );
    }

    // Add scale reference human figure
    final personHeight = 1.8 * scale;
    final personWidth = 0.5 * scale;
    if (scaledHeight > 15 && scaledWidth > 10) {
      final personPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(
        Rect.fromLTWH(
          xOffset + (scaledWidth - personWidth) / 2,
          yOffset + (scaledHeight - personHeight),
          personWidth,
          personHeight,
        ),
        personPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// String Capitalization Extension
extension StringExtension on String {
  String capitalize() {
    return isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  }
}

// Tunnel Data Parser
List<Map<String, dynamic>>? getTunnelData() {
  if (_currentState?.githubCaveData == null || 
      !_currentState!.githubCaveData!.containsKey('TunnelData')) {
    return null;
  }

  try {
    final tunnelsString = _currentState!.githubCaveData!['TunnelData'].toString();
    return tunnelsString.split(':').map((segment) {
      final coords = segment.split(',').map(double.tryParse).toList();
      
      if (coords.length >= 6 && 
          coords.every((e) => e != null)) {
        return {
          'startX': coords[0]!,
          'startY': coords[1]!,
          'startZ': coords[2]!,
          'endX': coords[3]!,
          'endY': coords[4]!,
          'endZ': coords[5]!,
          'width': coords.length > 6 ? coords[6]! : 1.0,
          'height': coords.length > 7 ? coords[7]! : 1.0,
        };
      }
      return {};
    }).where((e) => e.isNotEmpty).toList();
  } catch (e) {
    print('Error parsing tunnel data: $e');
    return null;
  }
}

// Cave Breathing Forecast Widget
Widget buildCaveBreathingForecast() {
  final currentAirflow = calculateCurrentAirflow();
  final isInflow = currentAirflow < 0;

  return Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isInflow ? Icons.arrow_downward : Icons.arrow_upward,
                color: Colors.purple,
              ),
              const SizedBox(width: 8),
              const Text(
                'Cave Breathing Forecast',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      isInflow ? Icons.arrow_downward : Icons.arrow_upward,
                      color: Colors.purple,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isInflow ? 'INFLOW' : 'OUTFLOW',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getAirflowIntensity(currentAirflow.abs()),
                      style: TextStyle(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isInflow ? 'Currently: Inward Airflow' : 'Currently: Outward Airflow',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isInflow 
              ? 'Cold air entering the cave system'
              : 'Warm air exiting the cave system',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          buildAirflowExplanation(),
        ],
      ),
    ),
  );
}

// Add method for seasonal safety graph
Widget buildSeasonalSafetyGraph() {
  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Seasonal Safety Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 10,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 2,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 2,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                      reservedSize: 28,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                        if (value >= 0 && value < months.length) {
                          return Text(
                            months[value.toInt()],
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          );
                        }
                        return const Text('');
                      },
                      reservedSize: 30,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: generateSeasonalBarGroups(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.black.withOpacity(0.8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      const months = [
                        'January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'
                      ];
                      String month = months[group.x];
                      String safety = rod.toY >= 8 ? 'High Risk' : (rod.toY >= 4 ? 'Moderate Risk' : 'Low Risk');
                      return BarTooltipItem(
                        '$month\n$safety',
                        const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Safety Rating Index: Lower values indicate safer conditions',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              buildSafetyLegendItem(Colors.green, 'Low Risk'),
              const SizedBox(width: 16),
              buildSafetyLegendItem(Colors.orange, 'Moderate Risk'),
              const SizedBox(width: 16),
              buildSafetyLegendItem(Colors.red, 'High Risk'),
            ],
          ),
        ],
      ),
    ),
  );
}

// Helper to build legend item
Widget buildSafetyLegendItem(Color color, String label) {
  return Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

// Generate seasonal bar groups for chart
List<BarChartGroupData> generateSeasonalBarGroups() {
  List<double> safetyRatings = [];
  if (githubCaveData != null && githubCaveData!.containsKey('SeasonalRiskData')) {
    final data = githubCaveData!['SeasonalRiskData'].toString().split(',');
    safetyRatings = data.map((e) => double.tryParse(e.trim()) ?? 5.0).toList();
  } else {
    safetyRatings = getDefaultSeasonalData();
  }

  while (safetyRatings.length < 12) {
    safetyRatings.add(5.0);
  }

  return List.generate(12, (index) {
    final value = safetyRatings[index];
    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: value,
          color: value < 4 ? Colors.green : (value < 8 ? Colors.orange : Colors.red),
          width: 16,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(4),
          ),
        ),
      ],
    );
  });
}

// Default seasonal data based on climate patterns
List<double> getDefaultSeasonalData() {
  final isActiveStreamCave = githubCaveData?['Type']?.toString().toLowerCase().contains('stream') ?? false;
  final isAlpineCave = githubCaveData?['Type']?.toString().toLowerCase().contains('alpine') ?? false;

  if (isActiveStreamCave) {
    return [5.0, 6.0, 8.0, 9.0, 7.0, 5.0, 4.0, 3.0, 4.0, 6.0, 7.0, 6.0];
  } else if (isAlpineCave) {
    return [9.0, 8.0, 7.0, 6.0, 5.0, 3.0, 2.0, 2.0, 3.0, 5.0, 7.0, 8.0];
  } else {
    return [6.0, 5.0, 7.0, 8.0, 6.0, 4.0, 3.0, 3.0, 4.0, 5.0, 6.0, 7.0];
  }
}

// Implement the enhanced safety recommendations method
Widget buildEnhancedSafetyRecommendations() {
  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Safety Recommendations',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildSafetyItem(
            icon: Icons.access_time,
            title: 'Check Weather Forecast',
            description: 'Monitor weather changes before and during your visit',
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildSafetyItem(
            icon: Icons.battery_full,
            title: 'Carry Extra Batteries',
            description: 'Bring backup lighting and power sources',
            color: Colors.green,
          ),
          if (_hasFloodRisk()) ...[
            const SizedBox(height: 12),
            _buildSafetyItem(
              icon: Icons.crisis_alert,
              title: 'Flash Flood Awareness',
              description: 'Have evacuation plan and avoid lower passages',
              color: Colors.red,
            ),
          ],
          if (githubCaveData != null && githubCaveData!['Type']?.toString().toLowerCase().contains('vertical')) ...[
            const SizedBox(height: 12),
            _buildSafetyItem(
              icon: Icons.alt_route,
              title: 'Vertical Safety',
              description: 'Check all rigging and carry technical backup equipment',
              color: Colors.orange,
            ),
          ],
          const SizedBox(height: 12),
          _buildSafetyItem(
            icon: Icons.people,
            title: 'Cave With Partners',
            description: 'Never explore alone, use the buddy system',
            color: Colors.purple,
          ),
        ],
      ),
    ),
  );
}

// Implementation for _toggleMonitoring method
void toggleMonitoring() {
  // Implementation to toggle monitoring status
}

// Implementation for _checkIfMonitored
void checkIfMonitored() {
  // Implementation to check if the cave is monitored
}

// Add this tab method
Widget build3DModelTab() {
  return SingleChildScrollView(
    child: Column(
      children: [
        const SizedBox(height: 16),
        if (githubCaveData != null && githubCaveData!.containsKey('PointCloudURL') && githubCaveData!['PointCloudURL'].toString().isNotEmpty)
          PointCloudViewer(
            pointCloudUrl: githubCaveData!['PointCloudURL'],
            caveName: widget.cave.name,
          )
        else
          buildPointCloudFallback(),
      ],
    ),
  );
}

// Show demo point cloud or instruction to upload scan
Widget buildPointCloudFallback() {
  return Padding(
    padding: const EdgeInsets.all(24.0),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.view_in_ar, size: 80, color: Colors.grey[400]),
        const SizedBox(height: 16),
        const Text(
          'No 3D scan available',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'This cave does not have a point cloud scan yet. If you have scanned this cave, consider contributing your data.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('3D Cave Scan (Demo)')),
                  body: const PointCloudViewer(
                    pointCloudUrl: 'https://raw.githubusercontent.com/CaveSurveys/Upper-Long-Churn/refs/heads/main/Upper%20Long%20Churns%20-%20Pointcloud.xyz',
                    caveName: 'Upper Long Churn (Demo)',
                  ),
                ),
              ),
            );
          },
          child: const Text('View Demo Point Cloud'),
        ),
      ],
    ),
  );
}

Future<void> checkWeatherAlerts() async {
  if (weatherData != null) {
    final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase();
    if (conditions != null && (conditions.contains('rain') || conditions.contains('storm'))) {
      NotificationService.showNotification(
        title: 'Weather Alert for ${widget.cave.name}',
        body: 'Adverse weather conditions detected. Check weather tab for details.',
        payload: jsonEncode({'caveName': widget.cave.name}),
      );
    }
  }
    bool hasRainWarning0() {
    bool hasRainWarning() {
      final conditions = weatherData!['weather']?[0]?['main']?.toString().toLowerCase() ?? '';
      return conditions.contains('rain') || conditions.contains('storm');
    }
    final conditions = weatherData['weather']?[0]?['main']?.toString().toLowerCase() ?? '';
    return conditions.contains('rain') || conditions.contains('storm');  }
return null;
  return null;
return null;
  return null;
 return null;
 }
