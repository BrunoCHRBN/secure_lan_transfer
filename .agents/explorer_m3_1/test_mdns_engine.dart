import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ==========================================
// 1. DNS Packet Models
// ==========================================

enum DnsType {
  a(1),
  ptr(12),
  txt(16),
  aaaa(28),
  srv(33),
  any(255);

  final int value;
  const DnsType(this.value);

  static DnsType? fromValue(int v) {
    for (final t in DnsType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}

class DnsQuestion {
  final String name;
  final DnsType type;
  final int qclass;
  final bool unicastResponse;

  const DnsQuestion({
    required this.name,
    required this.type,
    this.qclass = 1, // IN
    this.unicastResponse = false,
  });
}

abstract class DnsRecord {
  final String name;
  final DnsType type;
  final int recordClass;
  final int ttl;
  final bool flushCache;

  const DnsRecord({
    required this.name,
    required this.type,
    this.recordClass = 1,
    this.ttl = 120,
    this.flushCache = false,
  });
}

class PtrRecord extends DnsRecord {
  final String domainName;

  const PtrRecord({
    required super.name,
    required this.domainName,
    super.ttl = 4500,
    super.flushCache = false,
  }) : super(type: DnsType.ptr);
}

class SrvRecord extends DnsRecord {
  final int priority;
  final int weight;
  final int port;
  final String target;

  const SrvRecord({
    required super.name,
    required this.port,
    required this.target,
    this.priority = 0,
    this.weight = 0,
    super.ttl = 120,
    super.flushCache = true,
  }) : super(type: DnsType.srv);
}

class TxtRecord extends DnsRecord {
  final Map<String, String> attributes;

  const TxtRecord({
    required super.name,
    required this.attributes,
    super.ttl = 120,
    super.flushCache = true,
  }) : super(type: DnsType.txt);
}

class ARecord extends DnsRecord {
  final InternetAddress address;

  const ARecord({
    required super.name,
    required this.address,
    super.ttl = 120,
    super.flushCache = true,
  }) : super(type: DnsType.a);
}

class DnsMessage {
  final int id;
  final bool isResponse;
  final bool isAuthoritative;
  final int responseCode;
  final List<DnsQuestion> questions;
  final List<DnsRecord> answers;
  final List<DnsRecord> authorities;
  final List<DnsRecord> additionals;

  const DnsMessage({
    this.id = 0,
    this.isResponse = false,
    this.isAuthoritative = false,
    this.responseCode = 0,
    this.questions = const [],
    this.answers = const [],
    this.authorities = const [],
    this.additionals = const [],
  });
}

// ==========================================
// 2. DNS Packet Serializer & Parser
// ==========================================

class DnsCodec {
  /// Encodes a DnsMessage into raw bytes.
  static Uint8List encode(DnsMessage message) {
    final builder = BytesBuilder();
    
    // Header (12 bytes)
    final header = ByteData(12);
    header.setUint16(0, message.id, Endian.big);
    
    int flags = 0;
    if (message.isResponse) flags |= 0x8400; // Response + Authoritative
    flags |= (message.responseCode & 0x0F);
    header.setUint16(2, flags, Endian.big);
    
    header.setUint16(4, message.questions.length, Endian.big);
    header.setUint16(6, message.answers.length, Endian.big);
    header.setUint16(8, message.authorities.length, Endian.big);
    header.setUint16(10, message.additionals.length, Endian.big);
    
    builder.add(header.buffer.asUint8List());

    // Questions
    for (final q in message.questions) {
      _encodeDomainName(builder, q.name);
      final qData = ByteData(4);
      qData.setUint16(0, q.type.value, Endian.big);
      int qclass = q.qclass & 0x7FFF;
      if (q.unicastResponse) qclass |= 0x8000;
      qData.setUint16(2, qclass, Endian.big);
      builder.add(qData.buffer.asUint8List());
    }

    // Records (Answers, Authorities, Additionals)
    for (final r in message.answers) {
      _encodeRecord(builder, r);
    }
    for (final r in message.authorities) {
      _encodeRecord(builder, r);
    }
    for (final r in message.additionals) {
      _encodeRecord(builder, r);
    }

    return builder.toBytes();
  }

  static void _encodeDomainName(BytesBuilder builder, String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean == '.') {
      builder.addByte(0);
      return;
    }
    final labels = clean.split('.').where((s) => s.isNotEmpty);
    for (final label in labels) {
      final bytes = utf8.encode(label);
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
    builder.addByte(0);
  }

  static void _encodeRecord(BytesBuilder builder, DnsRecord record) {
    _encodeDomainName(builder, record.name);
    
    final rdataBuilder = BytesBuilder();
    
    if (record is PtrRecord) {
      _encodeDomainName(rdataBuilder, record.domainName);
    } else if (record is SrvRecord) {
      final srvHdr = ByteData(6);
      srvHdr.setUint16(0, record.priority, Endian.big);
      srvHdr.setUint16(2, record.weight, Endian.big);
      srvHdr.setUint16(4, record.port, Endian.big);
      rdataBuilder.add(srvHdr.buffer.asUint8List());
      _encodeDomainName(rdataBuilder, record.target);
    } else if (record is TxtRecord) {
      if (record.attributes.isEmpty) {
        rdataBuilder.addByte(0);
      } else {
        for (final entry in record.attributes.entries) {
          final str = '${entry.key}=${entry.value}';
          final b = utf8.encode(str);
          if (b.length <= 255) {
            rdataBuilder.addByte(b.length);
            rdataBuilder.add(b);
          }
        }
      }
    } else if (record is ARecord) {
      rdataBuilder.add(record.address.rawAddress);
    }

    final rdata = rdataBuilder.toBytes();

    final meta = ByteData(10);
    meta.setUint16(0, record.type.value, Endian.big);
    int rclass = record.recordClass & 0x7FFF;
    if (record.flushCache) rclass |= 0x8000;
    meta.setUint16(2, rclass, Endian.big);
    meta.setUint32(4, record.ttl, Endian.big);
    meta.setUint16(8, rdata.length, Endian.big);

    builder.add(meta.buffer.asUint8List());
    builder.add(rdata);
  }

  /// Decodes raw bytes into a DnsMessage.
  static DnsMessage decode(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('DNS packet too short for header (< 12 bytes)');
    }
    final byteData = ByteData.sublistView(bytes);
    final id = byteData.getUint16(0, Endian.big);
    final flags = byteData.getUint16(2, Endian.big);
    final qdCount = byteData.getUint16(4, Endian.big);
    final anCount = byteData.getUint16(6, Endian.big);
    final nsCount = byteData.getUint16(8, Endian.big);
    final arCount = byteData.getUint16(10, Endian.big);

    final isResponse = (flags & 0x8000) != 0;
    final isAuthoritative = (flags & 0x0400) != 0;
    final rcode = flags & 0x000F;

    int offset = 12;

    // Decode questions
    final questions = <DnsQuestion>[];
    for (int i = 0; i < qdCount; i++) {
      final (name, nextOffset) = _decodeDomainName(bytes, offset);
      offset = nextOffset;
      if (offset + 4 > bytes.length) break;
      final qtypeVal = byteData.getUint16(offset, Endian.big);
      final qclassVal = byteData.getUint16(offset + 2, Endian.big);
      offset += 4;
      
      final type = DnsType.fromValue(qtypeVal) ?? DnsType.any;
      final unicast = (qclassVal & 0x8000) != 0;
      final qclass = qclassVal & 0x7FFF;
      questions.add(DnsQuestion(
        name: name,
        type: type,
        qclass: qclass,
        unicastResponse: unicast,
      ));
    }

    // Decode records helper
    List<DnsRecord> decodeRecords(int count) {
      final records = <DnsRecord>[];
      for (int i = 0; i < count; i++) {
        if (offset >= bytes.length) break;
        final (name, nextOffset) = _decodeDomainName(bytes, offset);
        offset = nextOffset;
        if (offset + 10 > bytes.length) break;

        final typeVal = byteData.getUint16(offset, Endian.big);
        final classVal = byteData.getUint16(offset + 2, Endian.big);
        final ttl = byteData.getUint32(offset + 4, Endian.big);
        final rdLen = byteData.getUint16(offset + 8, Endian.big);
        offset += 10;

        if (offset + rdLen > bytes.length) break;
        final rdataBytes = bytes.sublist(offset, offset + rdLen);
        final rdataEnd = offset + rdLen;

        final type = DnsType.fromValue(typeVal);
        final flushCache = (classVal & 0x8000) != 0;
        final rclass = classVal & 0x7FFF;

        if (type == DnsType.ptr) {
          final (ptrName, _) = _decodeDomainName(bytes, offset);
          records.add(PtrRecord(
            name: name,
            domainName: ptrName,
            ttl: ttl,
            flushCache: flushCache,
          ));
        } else if (type == DnsType.srv) {
          if (rdLen >= 6) {
            final srvData = ByteData.sublistView(bytes, offset, offset + 6);
            final priority = srvData.getUint16(0, Endian.big);
            final weight = srvData.getUint16(2, Endian.big);
            final port = srvData.getUint16(4, Endian.big);
            final (target, _) = _decodeDomainName(bytes, offset + 6);
            records.add(SrvRecord(
              name: name,
              port: port,
              target: target,
              priority: priority,
              weight: weight,
              ttl: ttl,
              flushCache: flushCache,
            ));
          }
        } else if (type == DnsType.txt) {
          final attrs = <String, String>{};
          int txtOff = 0;
          while (txtOff < rdataBytes.length) {
            final len = rdataBytes[txtOff];
            txtOff++;
            if (txtOff + len <= rdataBytes.length && len > 0) {
              final str = utf8.decode(rdataBytes.sublist(txtOff, txtOff + len), allowMalformed: true);
              final eqIdx = str.indexOf('=');
              if (eqIdx > 0) {
                attrs[str.substring(0, eqIdx)] = str.substring(eqIdx + 1);
              } else if (str.isNotEmpty) {
                attrs[str] = '';
              }
              txtOff += len;
            } else {
              break;
            }
          }
          records.add(TxtRecord(
            name: name,
            attributes: attrs,
            ttl: ttl,
            flushCache: flushCache,
          ));
        } else if (type == DnsType.a) {
          if (rdLen == 4) {
            final addr = InternetAddress.fromRawAddress(rdataBytes);
            records.add(ARecord(
              name: name,
              address: addr,
              ttl: ttl,
              flushCache: flushCache,
            ));
          }
        }

        offset = rdataEnd;
      }
      return records;
    }

    final answers = decodeRecords(anCount);
    final authorities = decodeRecords(nsCount);
    final additionals = decodeRecords(arCount);

    return DnsMessage(
      id: id,
      isResponse: isResponse,
      isAuthoritative: isAuthoritative,
      responseCode: rcode,
      questions: questions,
      answers: answers,
      authorities: authorities,
      additionals: additionals,
    );
  }

  static (String, int) _decodeDomainName(Uint8List bytes, int offset) {
    final labels = <String>[];
    int currentOffset = offset;
    int? nextHeaderOffset;
    int jumps = 0;

    while (currentOffset < bytes.length && jumps < 10) {
      final len = bytes[currentOffset];
      if (len == 0) {
        currentOffset++;
        break;
      }
      // Check for compression pointer (top 2 bits 11)
      if ((len & 0xC0) == 0xC0) {
        if (currentOffset + 1 >= bytes.length) break;
        final pointerOffset = ((len & 0x3F) << 8) | bytes[currentOffset + 1];
        if (nextHeaderOffset == null) {
          nextHeaderOffset = currentOffset + 2;
        }
        currentOffset = pointerOffset;
        jumps++;
        continue;
      }

      currentOffset++;
      if (currentOffset + len > bytes.length) break;
      final labelBytes = bytes.sublist(currentOffset, currentOffset + len);
      labels.add(utf8.decode(labelBytes, allowMalformed: true));
      currentOffset += len;
    }

    final fullDomain = labels.join('.');
    return (fullDomain, nextHeaderOffset ?? currentOffset);
  }
}

// ==========================================
// 3. Test Runner
// ==========================================

void main() async {
  print('--- Testing Pure Dart DNS-SD Packet Codec ---');

  final originalQuery = DnsMessage(
    id: 0,
    questions: [
      const DnsQuestion(
        name: '_securetransfer._tcp.local',
        type: DnsType.ptr,
        unicastResponse: true,
      ),
    ],
  );

  final queryBytes = DnsCodec.encode(originalQuery);
  print('Encoded query bytes: ${queryBytes.length}');

  final decodedQuery = DnsCodec.decode(queryBytes);
  print('Decoded Question: name=${decodedQuery.questions.first.name}, type=${decodedQuery.questions.first.type.name}, QU=${decodedQuery.questions.first.unicastResponse}');
  assert(decodedQuery.questions.first.name == '_securetransfer._tcp.local');
  assert(decodedQuery.questions.first.type == DnsType.ptr);

  // Response Packet
  final originalResponse = DnsMessage(
    id: 0,
    isResponse: true,
    isAuthoritative: true,
    answers: [
      const PtrRecord(
        name: '_securetransfer._tcp.local',
        domainName: 'Pixel 7 Pro._securetransfer._tcp.local',
        ttl: 4500,
      ),
      const SrvRecord(
        name: 'Pixel 7 Pro._securetransfer._tcp.local',
        port: 42385,
        target: 'pixel7pro.local',
        ttl: 120,
      ),
      const TxtRecord(
        name: 'Pixel 7 Pro._securetransfer._tcp.local',
        attributes: {
          'id': 'e8b2c451-91a3-4a11-b0e2-df9824619712',
          'name': 'Pixel 7 Pro',
          'os': 'android',
          'port': '42385',
          'proto': '1',
        },
        ttl: 120,
      ),
      ARecord(
        name: 'pixel7pro.local',
        address: InternetAddress('192.168.1.50'),
        ttl: 120,
      ),
    ],
  );

  final respBytes = DnsCodec.encode(originalResponse);
  print('Encoded response bytes: ${respBytes.length}');

  final decodedResp = DnsCodec.decode(respBytes);
  print('Decoded Answers count: ${decodedResp.answers.length}');
  for (final a in decodedResp.answers) {
    if (a is PtrRecord) {
      print(' - PTR: ${a.name} -> ${a.domainName} (TTL ${a.ttl})');
    } else if (a is SrvRecord) {
      print(' - SRV: ${a.name} -> ${a.target}:${a.port} (TTL ${a.ttl})');
    } else if (a is TxtRecord) {
      print(' - TXT: ${a.name} -> ${a.attributes} (TTL ${a.ttl})');
    } else if (a is ARecord) {
      print(' - A: ${a.name} -> ${a.address.address} (TTL ${a.ttl})');
    }
  }

  assert(decodedResp.answers.length == 4);
  final txtRec = decodedResp.answers.whereType<TxtRecord>().first;
  assert(txtRec.attributes['id'] == 'e8b2c451-91a3-4a11-b0e2-df9824619712');
  assert(txtRec.attributes['name'] == 'Pixel 7 Pro');
  assert(txtRec.attributes['os'] == 'android');
  assert(txtRec.attributes['port'] == '42385');
  assert(txtRec.attributes['proto'] == '1');

  final srvRec = decodedResp.answers.whereType<SrvRecord>().first;
  assert(srvRec.port == 42385);

  print('=== ALL DNS-SD CODEC TESTS PASSED! ===');
}
