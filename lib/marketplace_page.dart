import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'offline_store.dart';

class MarketplacePage extends StatefulWidget {
  const MarketplacePage({super.key});

  @override
  State<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends State<MarketplacePage> {
  static const _registeredPartnersKey = 'marketplace_registered_partners_v1';

  final TextEditingController _businessController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _locationController =
      TextEditingController(text: 'Johannesburg');
  final TextEditingController _searchAreaController =
      TextEditingController(text: 'Johannesburg');

  String _partnerType = 'Gym';
  String _selectedPlan = 'Launch Free';
  String? _message;

  List<_RegisteredPartner> _registeredPartners = const [];
  List<_RegisteredPartner> _results = const [];

  @override
  void initState() {
    super.initState();
    _loadRegisteredPartners();
  }

  @override
  void dispose() {
    _businessController.dispose();
    _contactController.dispose();
    _locationController.dispose();
    _searchAreaController.dispose();
    super.dispose();
  }

  Future<void> _loadRegisteredPartners() async {
    final store = await OfflineStore.getInstance();
    final raw = store.getString(_registeredPartnersKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List;
      final loaded = decoded
          .whereType<Map>()
          .map((entry) => _RegisteredPartner.fromJson(
              Map<String, dynamic>.from(entry.cast<String, dynamic>())))
          .toList();

      if (!mounted) return;
      setState(() => _registeredPartners = loaded);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _registeredPartners = const [];
        _message = 'Could not load registered marketplace partners.';
      });
    }
  }

  Future<void> _saveRegisteredPartners(
      List<_RegisteredPartner> partners) async {
    final store = await OfflineStore.getInstance();
    await store.setString(
      _registeredPartnersKey,
      jsonEncode(partners.map((partner) => partner.toJson()).toList()),
    );
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.parse(raw);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _message = 'Could not open link right now.');
    }
  }

  Future<void> _searchPartners(String type) async {
    final location = _searchAreaController.text.trim();
    if (location.isEmpty) {
      setState(() {
        _message = 'Add your area first so we can find nearby options.';
        _results = const [];
      });
      return;
    }

    final locationLower = location.toLowerCase();
    final matches = _registeredPartners
        .where((partner) =>
            partner.type == type &&
            (partner.area.toLowerCase().contains(locationLower) ||
                locationLower.contains(partner.area.toLowerCase())))
        .toList();

    if (matches.isNotEmpty) {
      setState(() {
        _results = matches;
        _message =
            'Showing registered $type listings in or near $location first.';
      });
      return;
    }

    setState(() {
      _results = const [];
      _message =
          'No registered $type found in $location yet. Opening nearby web results.';
    });

    if (type == 'Gym') {
      await _openLink('https://www.google.com/maps/search/gym+near+$location');
    } else {
      await _openLink(
          'https://www.google.com/maps/search/personal+trainer+near+$location');
    }
  }

  Future<void> _submitLead() async {
    final business = _businessController.text.trim();
    final contact = _contactController.text.trim();
    final area = _locationController.text.trim();

    if (business.isEmpty || contact.isEmpty || area.isEmpty) {
      setState(() {
        _message =
            'Please add business name, contact details and your operating area.';
      });
      return;
    }

    final newPartner = _RegisteredPartner(
      name: business,
      type: _partnerType,
      area: area,
      distanceHint: 'Nearby',
      details: 'Registered via in-app marketplace form',
      contact: contact,
    );

    final updated = [newPartner, ..._registeredPartners];
    await _saveRegisteredPartners(updated);

    if (!mounted) return;
    setState(() {
      _registeredPartners = updated;
      _message =
          'Thanks! $_partnerType registration saved for $_selectedPlan. We will contact $contact.';
      _businessController.clear();
      _contactController.clear();
      _locationController.text = area;
      _partnerType = 'Gym';
      _selectedPlan = 'Launch Free';
    });
  }

  @override
  Widget build(BuildContext context) {
    final plans = [
      _Plan(
          name: 'Launch Free',
          monthlyFee: 'R0 / month',
          setupFee: 'No setup fee',
          benefits:
              '1 listing, up to 100 profile views/month, 2 offers/month, WhatsApp lead button'),
      _Plan(
          name: 'Starter',
          monthlyFee: 'R149 / month',
          setupFee: 'No setup fee',
          benefits:
              'Up to 2 listings, 8 offers/month, follower push placement, basic performance insights'),
      _Plan(
          name: 'Growth',
          monthlyFee: 'R399 / month',
          setupFee: 'R149 once-off setup',
          benefits:
              'Up to 5 listings, 20 offers/month, boosted search spots, lead conversion analytics'),
      _Plan(
          name: 'Scale',
          monthlyFee: 'R899 / month',
          setupFee: 'R299 once-off setup',
          benefits:
              'Unlimited listings, priority placement, campaign support, optional 5% success-fee model'),
    ];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Text('Marketplace', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Gyms and personal trainers can advertise directly to FitQuest members.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Starting out? Begin with Launch Free and validate demand first. Upgrade once ads bring consistent paying clients.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchAreaController,
              decoration: const InputDecoration(
                labelText: 'Search area',
                hintText: 'Example: Johannesburg, Sandton',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                      onPressed: () => _searchPartners('Gym'),
                      icon: const Icon(Icons.fitness_center),
                      label: const Text('Find gyms')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _searchPartners('Personal Trainer'),
                      icon: const Icon(Icons.person_search_outlined),
                      label: const Text('Find trainers')),
                ),
              ],
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Registered on FitQuest nearby',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              for (final partner in _results)
                Card(
                  child: ListTile(
                    leading: Icon(
                        partner.type == 'Gym'
                            ? Icons.fitness_center
                            : Icons.person_pin_circle_outlined,
                        color: Colors.teal),
                    title: Text(partner.name),
                    subtitle: Text(
                        '${partner.area} - ${partner.distanceHint}\n${partner.details}'),
                    isThreeLine: true,
                    trailing: FilledButton(
                      onPressed: () => setState(() => _message =
                          'Contact request sent to ${partner.name}.'),
                      child: const Text('Connect'),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            ...plans.map((plan) => Card(
                  child: ListTile(
                    title: Text(plan.name),
                    subtitle: Text(
                        '${plan.monthlyFee} - ${plan.setupFee}\n${plan.benefits}'),
                    isThreeLine: true,
                    trailing: _selectedPlan == plan.name
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () => setState(() => _selectedPlan = plan.name),
                  ),
                )),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Advertise with FitQuest',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _partnerType,
                      items: const [
                        DropdownMenuItem(value: 'Gym', child: Text('Gym')),
                        DropdownMenuItem(
                            value: 'Personal Trainer',
                            child: Text('Personal Trainer')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _partnerType = value);
                      },
                      decoration:
                          const InputDecoration(labelText: 'Partner type'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _businessController,
                      decoration:
                          const InputDecoration(labelText: 'Business name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contactController,
                      decoration: const InputDecoration(
                          labelText: 'Contact email or phone'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                          labelText: 'Operating area / suburb'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _submitLead,
                      icon: const Icon(Icons.send_outlined),
                      label: Text('Submit $_selectedPlan lead'),
                    ),
                  ],
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Plan {
  final String name;
  final String monthlyFee;
  final String setupFee;
  final String benefits;

  const _Plan({
    required this.name,
    required this.monthlyFee,
    required this.setupFee,
    required this.benefits,
  });
}

class _RegisteredPartner {
  final String name;
  final String type;
  final String area;
  final String distanceHint;
  final String details;
  final String? contact;

  const _RegisteredPartner({
    required this.name,
    required this.type,
    required this.area,
    required this.distanceHint,
    required this.details,
    this.contact,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'area': area,
        'distanceHint': distanceHint,
        'details': details,
        'contact': contact,
      };

  factory _RegisteredPartner.fromJson(Map<String, dynamic> json) =>
      _RegisteredPartner(
        name: (json['name'] as String?) ?? 'Unknown',
        type: (json['type'] as String?) ?? 'Gym',
        area: (json['area'] as String?) ?? 'Unknown area',
        distanceHint: (json['distanceHint'] as String?) ?? 'Nearby',
        details:
            (json['details'] as String?) ?? 'Registered via in-app marketplace',
        contact: json['contact'] as String?,
      );
}
