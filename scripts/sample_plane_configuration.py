"""One bounded read-only configuration snapshot; no calls or writes in AC8."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import struct
import time

import sample_plane_motion as motion


def pointer(value):
    if not 0x10000 <= value < 0x800000000000 or value % 8:
        raise ValueError("invalid aligned pointer")
    return value


class ConfigurationReader(motion.FlightReader):
    """Guards detect changes; external reads do not pin objects or form an atomic snapshot."""
    def __init__(self, read, base, ticket):
        self.guards = {}
        self.partial = {}
        super().__init__(read, base, ticket)

    def value(self, address, fmt):
        return struct.unpack('<' + fmt, self.read(address, struct.calcsize('<' + fmt)))[0]

    def object(self, address):
        address = pointer(address)
        header = self.read(address, 0x28)
        index = struct.unpack_from('<i', header, 12)[0]
        objects = self.base + 0xDC60CD0
        count = self.value(objects + 0x24, 'i')
        chunks = self.value(objects + 0x2C, 'i')
        if not 0 <= index < count <= 4_000_000 or not 0 <= index // 65536 < chunks <= 64:
            raise ValueError('object index outside current array')
        chunk_array = pointer(self.qword(objects + 0x10))
        chunk = pointer(self.qword(chunk_array + index // 65536 * 8))
        slot = chunk + (index % 65536) * 0x18
        if self.qword(slot) != address:
            raise ValueError('object slot mismatch')
        serial = self.value(slot + 0x10, 'i')
        if serial < 0:
            raise ValueError('invalid object serial')
        # Do not allocate serials in this read-only observer. Zero remains explicitly reported.
        identity = (header[:8] + header[12:], slot, serial)
        if address in self.guards and self.guards[address] != identity:
            raise ValueError('object identity changed')
        self.guards[address] = identity
        return dict(address=hex(address), index=index, serial=serial,
                    klass=hex(struct.unpack_from('<Q', header, 0x10)[0]),
                    outer=hex(struct.unpack_from('<Q', header, 0x20)[0]))

    def array(self, descriptor, stride, cap):
        raw = self.read(descriptor, 16)
        data, count, capacity = struct.unpack('<Qii', raw)
        if not 0 <= count <= cap or not count <= capacity <= 65536:
            raise ValueError('array bounds exceeded')
        payload = self.read(pointer(data), count * stride) if count else b''
        if self.read(descriptor, 16) != raw:
            raise ValueError('array changed during capture')
        return dict(data=hex(data), count=count, capacity=capacity, stride=stride,
                    raw_hex=payload.hex())

    def block(self, address, size):
        raw = self.read(address, size)
        return dict(address=hex(address), bytes=size, raw_hex=raw.hex(),
                    sha256=hashlib.sha256(raw).hexdigest())

    def registry(self, game_instance):
        owner = self.qword(game_instance + 0x910)
        if not owner:
            return dict(owner='0x0', result='unavailable_no_native_cleanup_owner')
        pointer(owner)
        owner_identity = self.object(owner)
        auto_init = self.value(owner + 0x1FA, 'B')
        address = owner + 0x2E0
        raw = self.read(address, 0x50)
        data = struct.unpack_from('<Q', raw)[0]
        count, free = struct.unpack_from('<i', raw, 8)[0], struct.unpack_from('<i', raw, 0x34)[0]
        external = struct.unpack_from('<Q', raw, 0x40)[0]
        buckets = struct.unpack_from('<i', raw, 0x48)[0]
        if not 0 <= free <= count <= 1_000_000:
            raise ValueError('registry sparse array bounds')
        candidates = []
        observed_reads = []
        for key in (0x434F4F5000000001, 0x434F4F5000000002):
            entries = []
            if count != free:
                if buckets <= 0 or buckets > 1_048_576 or buckets & (buckets - 1):
                    raise ValueError('registry bucket bounds')
                table = pointer(external) if external else address + 0x38
                if not external and buckets > 2:
                    raise ValueError('registry inline bucket bounds')
                bucket = ((key & 0xFFFFFFFF) + 23 * (key >> 32)) & (buckets - 1)
                index = self.value(table + bucket * 4, 'i')
                observed_reads.append((table + bucket * 4, struct.pack('<i', index)))
                visited = set()
                while index != -1:
                    if not 0 <= index < count or index in visited or len(visited) >= 128:
                        raise ValueError('registry chain invalid or exceeds bound')
                    visited.add(index)
                    item = self.read(pointer(data) + index * 24, 24)
                    observed_reads.append((data + index * 24, item))
                    stored, weak_index, serial, next_index = struct.unpack_from('<Qiii', item)
                    entries.append(dict(index=index, key=hex(stored), weak_index=weak_index, serial=serial))
                    index = next_index
            candidates.append(dict(key=hex(key), present=any(int(e['key'], 0) == key for e in entries),
                                   bucket_chain=entries))
        if (self.qword(game_instance + 0x910) != owner or self.read(address, 0x50) != raw
                or self.value(owner + 0x1FA, 'B') != auto_init
                or any(self.read(p, len(b)) != b for p, b in observed_reads)):
            raise ValueError('registry changed during observation')
        return dict(owner=hex(owner), identity=owner_identity, auto_init_flag_1fa=auto_init,
                    map=hex(address), count=count, free=free,
                    candidates=candidates, result='bounded_candidate_buckets_observed',
                    limitation='No reservation; later absence must be rechecked before Finish and cleanup.')

    def capture(self):
        self.check_identity()
        p, w = self.ticket['pawn'], self.ticket['world']
        result = self.partial
        result.update(source=self.object(p), world=self.object(w),
                      controller=self.object(self.ticket['controller']))
        parts = pointer(self.qword(p + 0x1328))
        result['upgrade_parts'] = self.object(parts)
        if int(result['upgrade_parts']['outer'], 0) != p:
            raise ValueError('parts Outer is not source plane')
        result['parts_arrays'] = {hex(o): self.array(parts + o, 4, 16) for o in (0x30, 0x40)}
        for a in result['parts_arrays'].values():
            a['int32_values'] = list(struct.unpack('<' + 'i' * a['count'], bytes.fromhex(a['raw_hex'])))
        result['parts_effects'] = self.array(parts + 0x1A7E8, 12, 64)
        result['parts_flags'] = {hex(o): self.value(parts + o, 'B') for o in (0x29, 0x9C)}
        table = pointer(self.qword(p + 0x3AB0))
        row_index = self.value(p + 0x3AB8, 'i')
        table_data, count = self.qword(table + 0x18), self.value(table + 0x20, 'i')
        if not 0 <= row_index < count <= 4096:
            raise ValueError('configured flight row unavailable')
        result['flight_table'] = dict(address=hex(table), data=hex(table_data), count=count,
                                     row_index=row_index,
                                     row=self.block(pointer(table_data) + row_index * 0x448, 0x448))
        result['models'] = {}
        for offset in (0x2268, 0x3C60):
            provider = self.qword(p + offset + 0x860)
            mode = self.value(p + offset + 0x8B4, 'B')
            if provider != p + 0xF48 or mode != (0 if offset == 0x2268 else 1):
                raise ValueError('model/provider mismatch')
            result['models'][hex(offset)] = dict(provider=hex(provider), mode=mode,
                configuration=self.block(p + offset + 0x9C0, 0x45C),
                pose=self.block(p + offset + 0x8D0, 0x78),
                physics_fields=self.block(p + offset + 0xE20, 0x10))
        spans = ((0xF98, 0x48), (0xDBA, 3), (0x1140, 4), (0x114C, 20),
                 (0x10A4, 4), (0x12CC, 8), (0x58B8, 0x28), (0x29BC, 4), (0x3A88, 8))
        result['plane_blocks'] = {hex(o): self.block(p + o, n) for o, n in spans}
        result['plane_fb8_ids'] = self.array(p + 0xFB8, 4, 32)
        gi = pointer(self.qword(w + 0x1D8))
        result['game_instance'] = self.object(gi)
        metadata = pointer(self.qword(gi + 0x878))
        result['parts_metadata'] = self.object(metadata)
        # Keep registry failure local: useful configuration evidence must survive it.
        try:
            result['network_registry'] = self.registry(gi)
        except Exception as error:
            result['network_registry'] = dict(result='unverified', error=str(error))
        network = self.qword(p + 0xED0)
        result['source_network'] = dict(address=hex(network))
        if network:
            result['source_network'].update(identity=self.object(network),
                                           net_id=hex(self.qword(network + 0x28)))
        activator = pointer(self.qword(p + 0x16A8))
        result['weapon_activator'] = self.object(activator)
        if int(result['weapon_activator']['outer'], 0) != p:
            raise ValueError('weapon activator Outer mismatch')
        component = pointer(self.qword(p + 0x18D8))
        result['component_18d8'] = dict(identity=self.object(component),
            owner_plane_1c0=hex(self.qword(component + 0x1C0)),
            fields_1d8=self.block(component + 0x1D8, 0x18))
        plane_1ae8 = self.qword(p + 0x1AE8)
        if (self.qword(component + 0x1C0) != p or self.qword(activator + 0x2D0) != p
                or self.qword(activator + 0x2D8) != plane_1ae8):
            raise ValueError('configured component backlinks mismatch')
        result['plane_1ae8'] = self.object(plane_1ae8) if plane_1ae8 else None
        weapon_component = pointer(self.qword(activator + 0x2E0))
        result['weapon_component_2e0'] = self.object(weapon_component)
        result['activator_initialized_byte_579'] = self.value(activator + 0x579, 'B')
        nested = self.qword(weapon_component + 0xA8)
        result['weapon_component_nested_a8'] = dict(address=hex(nested), classification='unclassified')
        if nested:
            try:
                result['weapon_component_nested_a8']['byte_119'] = self.value(pointer(nested) + 0x119, 'B')
            except Exception as error:
                result['weapon_component_nested_a8']['error'] = str(error)
        weapons = result['special_weapon_configs'] = self.array(activator + 0x158, 0x20, 16)
        result['weapon_classes'] = []
        cdo_links = []
        for i in range(weapons['count']):
            klass = struct.unpack_from('<Q', bytes.fromhex(weapons['raw_hex']), i * 0x20)[0]
            if not klass:
                result['weapon_classes'].append(None)
                continue
            entry = dict(klass=self.object(klass))
            cdo = pointer(self.qword(klass + 0x110))
            entry['cdo'] = self.object(cdo)
            if self.qword(cdo + 0x10) != klass or not self.value(cdo + 8, 'I') & 0x10:
                raise ValueError('weapon CDO class/flags mismatch')
            entry['cdo_weapon_enum_2b1'] = self.value(cdo + 0x2B1, 'B')
            cdo_links.append((klass, cdo))
            result['weapon_classes'].append(entry)
        for address in list(self.guards):
            # Check slot before reading a potentially retired UObject again.
            _, slot, serial = self.guards[address]
            if self.qword(slot) != address or self.value(slot + 0x10, 'i') != serial:
                raise ValueError('object retired during capture')
            self.object(address)
        if (self.qword(p + 0x1328) != parts or self.qword(p + 0x16A8) != activator
                or self.qword(p + 0x3AB0) != table or self.value(p + 0x3AB8, 'i') != row_index
                or self.qword(table + 0x18) != table_data or self.value(table + 0x20, 'i') != count
                or self.qword(w + 0x1D8) != gi or self.qword(gi + 0x878) != metadata
                or self.qword(p + 0x18D8) != component
                or self.qword(p + 0x1AE8) != plane_1ae8
                or self.qword(activator + 0x2E0) != weapon_component
                or self.qword(activator + 0x2D0) != p
                or self.qword(activator + 0x2D8) != plane_1ae8
                or any(self.qword(klass + 0x110) != cdo for klass, cdo in cdo_links)):
            raise ValueError('configuration graph changed')
        self.check_identity()
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--wait-ticket', type=int, default=900)
    args = parser.parse_args()
    if not 0 <= args.wait_ticket <= 900:
        parser.error('wait must be 0..900 seconds')
    session = json.loads((args.session / 'session.json').read_text(encoding='utf-8-sig'))
    if (session['extension'] != 'plane_configuration_probe.lua' or session.get('finished')
            or session['game_sha256'].lower() != motion.SHA):
        raise ValueError('need active configuration session')
    started = datetime.fromisoformat(session['started']).timestamp()
    reader = motion.WindowsReader(int(session['pid']), started)
    try:
        deadline = time.monotonic() + args.wait_ticket
        print('WAITING_FOR_CONFIGURATION_F8', flush=True)
        while True:
            paths = sorted(args.session.glob('configuration-ticket-*.tsv'),
                           key=lambda f: f.stat().st_mtime_ns, reverse=True)
            if paths:
                path = paths[0]
                ticket = motion.parse_ticket(path, reader.created, started, time.time())
                break
            if time.monotonic() >= deadline:
                raise TimeoutError('no configuration F8')
            time.sleep(.2)
        suffix = path.stem.removeprefix('configuration-ticket-')
        probe = None
        result = dict(result='reading', read_only=True, game_sha256=motion.SHA,
                      pid=session['pid'], base=hex(reader.base), ticket=ticket,
                      limitations='Nonatomic external observation, no lifetime pin. No setters, spawn, model configuration or flight readiness tested.')
        try:
            probe = ConfigurationReader(reader.read, reader.base, ticket)
            result['configuration'] = probe.capture()
            result['result'] = 'capture_complete'
        except Exception as error:
            result.update(result='capture_failed', error=str(error),
                          partial_configuration=probe.partial if probe else {})
        result['finished'] = datetime.now().astimezone().isoformat()
        output = args.session / ('configuration-sources-' + suffix + '.json')
        with output.open('x', encoding='utf-8') as f:
            json.dump(result, f, indent=2, allow_nan=False)
        print(json.dumps(dict(result=result['result'], output=str(output))), flush=True)
        if result['result'] != 'capture_complete':
            raise SystemExit(1)
    finally:
        reader.close()


if __name__ == '__main__':
    main()
