import 'package:busboard_nl/data/gtfs/headsign.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readableHeadsign', () {
    test("the feed's all-caps trip names read in title case", () {
      expect(readableHeadsign('AVALON MALL - MUN CENTRE - DOWNTOWN'), 'Avalon Mall - MUN Centre - Downtown');
      expect(readableHeadsign('STAVANGER DRIVE - THE VILLAGE'), 'Stavanger Drive - The Village');
      expect(readableHeadsign('MOUNT PEARL SQUARE - DONOVANS'), 'Mount Pearl Square - Donovans');
    });

    test('known acronyms stay in capitals', () {
      for (final a in ['MUN', 'HSC', 'CNA', 'NL', 'YYT', 'DFO', 'MI']) {
        expect(readableHeadsign('$a TERMINAL'), '$a Terminal', reason: a);
      }
      expect(readableHeadsign('MUN-CNA-MI'), 'MUN-CNA-MI');
      expect(readableHeadsign('EXPRESS HSC'), 'Express HSC');
    });

    test('other all-consonant words of 2 to 4 letters are acronyms too', () {
      expect(readableHeadsign('NLCHI - DOWNTOWN'), 'Nlchi - Downtown', reason: 'five letters is a word');
      expect(readableHeadsign('CBS - KELSEY DRIVE'), 'CBS - Kelsey Drive');
      expect(readableHeadsign('TD PLACE'), 'TD Place');
      expect(readableHeadsign('MUN VIA NLCC'), 'MUN via NLCC');
      expect(readableHeadsign('MY STOP'), 'My Stop', reason: 'a Y is a vowel here, so "MY" is a word');
    });

    test('St, Dr and Rd are street words, not acronyms', () {
      expect(readableHeadsign('MUN CENTRE - MOUNT SCIO RD - CNA'), 'MUN Centre - Mount Scio Rd - CNA');
      expect(readableHeadsign('KELSEY DR'), 'Kelsey Dr');
      expect(readableHeadsign('WATER ST'), 'Water St');
      expect(readableHeadsign("PORTUGAL COVE-ST. PHILIP'S"), "Portugal Cove-St. Philip's");
      expect(readableHeadsign("ST. JOHN'S"), "St. John's");
      // The other all-consonant street words read the same way.
      expect(readableHeadsign('CHURCHILL PL - LIONS CT - TOPSAIL BLVD - KENMOUNT CRT'),
          'Churchill Pl - Lions Ct - Topsail Blvd - Kenmount Crt');
    });

    test('small words are lower case inside a part, and capitalised at its start', () {
      expect(readableHeadsign('EXPRESS TO MUN CENTRE'), 'Express to MUN Centre');
      expect(readableHeadsign('DOWNTOWN VIA THE VILLAGE'), 'Downtown via the Village');
      expect(readableHeadsign('TO DOWNTOWN'), 'To Downtown');
    });

    test('numbers and brackets are kept', () {
      expect(readableHeadsign('ROUTE 10A - DOWNTOWN'), 'Route 10A - Downtown');
      expect(readableHeadsign('TORBAY RD (VIA AIRPORT)'), 'Torbay Rd (via Airport)');
    });

    test('mixed-case text is left as written', () {
      expect(readableHeadsign('MI - Eastern Health'), 'MI - Eastern Health');
      expect(readableHeadsign('Downtown'), 'Downtown');
      expect(readableHeadsign('Signal Hill Rd'), 'Signal Hill Rd');
    });

    test('empty, blank and letterless text is kept', () {
      expect(readableHeadsign(''), '');
      expect(readableHeadsign('  '), '  ');
      expect(readableHeadsign('10 - 11'), '10 - 11');
    });
  });
}
