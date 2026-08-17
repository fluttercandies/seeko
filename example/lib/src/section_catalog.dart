import 'package:flutter/material.dart';

@immutable
class CatalogSection {
  const CatalogSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<CatalogItem> items;
}

@immutable
class CatalogItem {
  const CatalogItem({
    required this.name,
    required this.description,
    required this.height,
  });

  final String name;
  final String description;
  final double height;
}

const List<CatalogSection> catalogSections = <CatalogSection>[
  CatalogSection(
    id: 'popular',
    label: 'Popular',
    icon: Icons.local_fire_department_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'House favorites',
        description: 'Frequently reordered dishes from the current menu.',
        height: 112,
      ),
      CatalogItem(
        name: 'Quick lunch',
        description: 'Balanced combinations prepared for a short break.',
        height: 132,
      ),
      CatalogItem(
        name: 'Chef picks',
        description: 'Seasonal ingredients with a changing daily pairing.',
        height: 152,
      ),
    ],
  ),
  CatalogSection(
    id: 'breakfast',
    label: 'Breakfast',
    icon: Icons.free_breakfast_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'Morning plate',
        description: 'Eggs, roasted vegetables, grains, and toasted sourdough.',
        height: 144,
      ),
      CatalogItem(
        name: 'Fruit and oats',
        description: 'Warm oats with fresh fruit, seeds, and cultured yogurt.',
        height: 126,
      ),
      CatalogItem(
        name: 'Breakfast sandwich',
        description: 'Folded egg, greens, and sharp cheese on a seeded roll.',
        height: 138,
      ),
    ],
  ),
  CatalogSection(
    id: 'noodles',
    label: 'Noodles',
    icon: Icons.ramen_dining_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'Sesame noodles',
        description: 'Hand-pulled noodles, sesame dressing, cucumber, chili.',
        height: 154,
      ),
      CatalogItem(
        name: 'Clear broth noodles',
        description: 'Slow broth, greens, mushrooms, and aromatic herbs.',
        height: 136,
      ),
      CatalogItem(
        name: 'Market vegetable noodles',
        description: 'A rotating mix of vegetables with a bright soy glaze.',
        height: 162,
      ),
    ],
  ),
  CatalogSection(
    id: 'rice',
    label: 'Rice Bowls',
    icon: Icons.rice_bowl_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'Ginger chicken bowl',
        description: 'Grilled chicken, ginger scallion sauce, greens, rice.',
        height: 148,
      ),
      CatalogItem(
        name: 'Miso mushroom bowl',
        description: 'Roasted mushrooms, miso glaze, pickles, brown rice.',
        height: 132,
      ),
      CatalogItem(
        name: 'Crisp tofu bowl',
        description: 'Tofu, cabbage, herbs, toasted peanuts, and lime.',
        height: 156,
      ),
    ],
  ),
  CatalogSection(
    id: 'drinks',
    label: 'Drinks',
    icon: Icons.local_cafe_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'Cold brew',
        description: 'Single-origin coffee steeped slowly and served chilled.',
        height: 116,
      ),
      CatalogItem(
        name: 'Citrus tea',
        description: 'Black tea, seasonal citrus, and a restrained sweetness.',
        height: 128,
      ),
      CatalogItem(
        name: 'Sparkling botanical',
        description: 'Herbs, cucumber, lime, and sparkling mineral water.',
        height: 142,
      ),
    ],
  ),
  CatalogSection(
    id: 'desserts',
    label: 'Desserts',
    icon: Icons.cake_outlined,
    items: <CatalogItem>[
      CatalogItem(
        name: 'Cocoa tart',
        description: 'Dark cocoa custard, sea salt, and a crisp pastry shell.',
        height: 146,
      ),
      CatalogItem(
        name: 'Citrus cake',
        description: 'Olive oil cake with citrus curd and cultured cream.',
        height: 138,
      ),
      CatalogItem(
        name: 'Seasonal fruit',
        description: 'Peak-season fruit with mint and a light ginger syrup.',
        height: 126,
      ),
    ],
  ),
];

CatalogSection sectionById(List<CatalogSection> sections, String id) =>
    sections.firstWhere((CatalogSection section) => section.id == id);
