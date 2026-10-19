# Shopkeeper Pro — Business Category Catalog

**Purpose:** One shared business platform with a core POS/accounting layer and optional vertical modules. This is a scope catalogue, not a claim that every category is implemented.

## Shared modules

- Account/shop/branch setup and staff roles
- POS, invoices, payments and returns
- Product/service catalogue, purchases and suppliers
- Customers, credit/udhaar and ledgers
- Expenses, cash/bank accounts and financial reports
- Stock movements, transfers and valuation
- PDF/export/share, backup/restore, sync and audit history
- Permissions, account isolation and data export/deletion

## Category catalogue

| Category | Examples of item or record types | Category-specific capabilities to plan |
|---|---|---|
| General Store / Retail | Food, household goods, daily-use items | Barcode, units, stock, expiry where relevant, supplier and customer dues |
| Karyana / Grocery | Rice, flour, pulses, oil, spices, beverages | Weight/fractional units, expiry, batch, low stock, credit ledger |
| Supermarket | Packaged goods, household, personal care | Barcode, multi-counter cashiers, shift closing, price labels |
| Wholesale / Distribution | Cartons, cases, bulk units | Price tiers, unit conversion, route delivery, credit limits |
| Mobile Shop / Electronics | New and used phones, accessories, parts | IMEI/serial, used-device intake, repair/software jobs, warranty |
| Mobile Spare Parts | Panels, charging ports/base boards, batteries, flex, speaker/mic, camera, connectors, ICs | Device compatibility, quality grade, part number, warranty |
| Computer / Laptop | Laptops, desktops, RAM, SSD, keyboard, adapters, screens | Serial number, specifications, compatible parts, warranty/repair |
| Bike / Motorcycle Spare Parts | Filters, brake pads, cables, chains, sprockets, lights, mirrors | Make/model/year fitment, OEM/aftermarket, cross-reference |
| Car / Auto Spare Parts | Filters, belts, brake parts, sensors, lamps, body parts | Make/model/year/engine compatibility, bin location, warranty |
| Truck / Bus / Heavy Parts | Heavy-duty filters, tyres, bearings, engine/brake parts | Vehicle compatibility, bulk units, supplier lead time |
| Home Appliance Parts | Fridge, AC, washing machine, fan and appliance parts | Brand/model compatibility, specifications, repair links |
| Electrical / Electronics Parts | Switches, sockets, breakers, wire, connectors, components | Ratings/specifications, pack/length units, warranty |
| Industrial / Agricultural / Generator Parts | Bearings, belts, pumps, tractor and generator parts | Machine/engine compatibility, serial/batch, cross-reference |
| Plumbing / Sanitary | Pipes, elbows, taps, valves, fittings, bathroom accessories | Diameter/size/material, unit conversion, delivery |
| Clothing / Garments | Shirts, suits, fabric, uniforms | Size/colour variants, barcode, exchange and alteration |
| Shoes / Footwear | Shoes, sandals, slippers | Size/colour variants, SKU, exchange |
| Cosmetics / Beauty Products | Lipstick, foundation, mascara, powder, skincare, sunscreen, shampoo, hair colour, perfume, body spray, beauty tools | Brand, shade/colour, size, batch/expiry, barcode, supplier, stock and return policy |
| Furniture / Carpet / Crockery | Tables, chairs, sofas, carpets, plates, cookware, sets | Dimensions, material, set/piece, fragile handling, delivery/custom orders |
| Restaurant / Cafe / Bakery | Menu items, ingredients, drinks, bakery products | Recipe/ingredient stock, tables, kitchen tickets, wastage, takeaway/delivery |
| Hotel / Hospitality | Rooms, bookings, services, restaurant items | Reservation, check-in/out, room status, service charges, housekeeping |
| Car / Motorcycle Showroom | New/used cars and bikes | VIN/chassis/engine, documents, inspection, deal costs and margin |
| Vehicle Workshop | Service jobs, labour, oils, filters, replacement parts | Job cards, estimates, technician, maintenance and service history |
| Passenger Transport | Routes, stops, tickets, seats | Timetable, fare, passenger manifest, cancellations/refunds |
| Trucking / Fleet | Vehicles, drivers, trips, fuel, tolls | Trip cost, maintenance, driver settlement, vehicle documents |
| Cargo / Delivery | Consignments, packages, freight, COD | Tracking events, proof of delivery, shortage/damage claims |
| Rent a Car | Vehicles, bookings, deposits, rental contracts | Availability, agreement, return inspection, mileage/fuel, damage |
| Public Service Counter | Applications, tokens, document checklists, fees | Queue, reference numbers, status and controlled access; customise to actual lawful service |
| Private Services / Agency | Projects, tasks, client invoices, deliverables | Quotes, milestones, timesheets, expense and project margin |
| Salon / Spa | Services, products, appointments, packages | Staff calendar, bookings, service sales and commissions |
| School / Academy | Students, classes, fees, attendance | Admissions, guardian records, fee plans, arrears, privacy controls |
| Clinic / Healthcare | Appointments and service billing | Restricted data access; clinical records need a separate compliance review |
| Agriculture / Farm Supplies | Seeds, fertilizer, tools, harvest lots | Seasonal stock/costs, supplier, lot and crop records |
| Construction / Contractor | Materials, projects, labour, subcontractors | Estimates/BOQ, project costs, milestones and payments |
| Other / Custom Business | User-defined products/services/fields | Reusable POS, catalogue, ledger, reports and configurable fields |

## Cross-category rules

1. Every record must belong to the correct account/shop and be permission-checked in services and cloud rules.
2. A category may enable suggested modules, but owners can only activate modules whose dependencies and permissions are supported.
3. Keep category-specific data separate from common bill/ledger records, linked by stable IDs.
4. Do not treat module IDs as proof of implemented screens or workflows.
5. Medical, public-sector, identity and device-unlock workflows require specific legal/privacy review before release.
6. Keep Cosmetics as a selectable category; batch/expiry handling must be tested before claiming it is production-ready.
