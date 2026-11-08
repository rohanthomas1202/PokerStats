#!/usr/bin/env python3
"""Regenerate the independent export goldens from dataset.json (no app code)."""
import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SESSION_COLUMNS = 'id start_time end_time location stakes notes game_type status buy_in rebuys add_ons cash_out tip_rake tilt_level energy_level focus_level table_config currency'.split()
HAND_COLUMNS = 'id session_id hand_number played_at preflop_action faced_3bet three_bet_response postflop_result did_cbet notes position'.split()
MONEY = 'buy_in rebuys add_ons cash_out tip_rake'.split()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def csv_cell(value):
    if value is None:
        text = ''
    elif isinstance(value, str):
        text = "'" + value if value.startswith(tuple("=+-@\t\r")) else value
    else:
        text = canonical(value)
    if any(c in text for c in ',"\r\n'):
        return '"' + text.replace('"', '""') + '"'
    return text


def write_csv(name, columns, rows):
    lines = [','.join(columns)]
    lines += [','.join(csv_cell(row[column]) for column in columns) for row in rows]
    (ROOT / name).write_text('\n'.join(lines) + '\n')


def main():
    dataset = json.loads((ROOT / 'dataset.json').read_text())
    sessions = sorted(dataset['sessions'], key=lambda row: row['id'])
    hands = sorted(dataset['hands'], key=lambda row: row['id'])
    for row in sessions:
        row['currency'] = dataset['currency']
        for column in MONEY:
            rounded = Decimal(str(row[column])).quantize(Decimal('.01'), rounding=ROUND_HALF_UP)
            row[column] = int(rounded) if rounded == rounded.to_integral() else float(rounded)
    document = {'format_version': 1, 'sessions': sessions, 'hands': hands}
    (ROOT / 'pokerstats-export.json').write_text(canonical(document) + '\n')
    write_csv('sessions.csv', SESSION_COLUMNS, sessions)
    write_csv('hands.csv', HAND_COLUMNS, hands)


if __name__ == '__main__':
    main()
