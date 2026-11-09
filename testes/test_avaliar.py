#!/usr/bin/env python3
# seiva · JulianoSSR · MIT
import copy
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import avaliar

class EvaluationTests(unittest.TestCase):
    def rows(self):
        base=dict(run='synthetic',case='fix-1',kind='simples',split='avaliacao',real=False,
            models=[dict(app='fake',version='test',model='fixture',effort='none')],conditions={'seed':1},
            acceptance=['same-test'],passed=True,tokens=dict(input=100,output=100,cache_read=0,cache_write=0,total=200),
            monitor_tokens=10,duration_seconds=1,defects_detected=1,defects_escaped=0,false_positives=0,
            rework_tokens=0,evidence=['synthetic fixture, not real tokens'])
        return [dict(copy.deepcopy(base),mode=mode) for mode in sorted(avaliar.MODES)]
    def test_simulation_never_proves_economy(self):
        rows=self.rows();next(r for r in rows if r['mode']=='seiva')['tokens']['total']=100
        self.assertFalse(avaliar.aggregate(rows)['comparisons'][0]['economy_proven'])
    def test_real_economy_requires_equivalent_quality(self):
        rows=self.rows()
        for r in rows:r['real']=True
        seiva=next(r for r in rows if r['mode']=='seiva');seiva['tokens']['total']=100;seiva['passed']=False
        self.assertFalse(avaliar.aggregate(rows)['comparisons'][0]['economy_proven'])
    def test_higher_seiva_cost_visible(self):
        rows=self.rows();next(r for r in rows if r['mode']=='seiva')['tokens']['total']=300
        self.assertEqual(avaliar.aggregate(rows)['comparisons'][0]['difference_seiva_vs_direct'],100)
    def test_incompatible_acceptance_rejected(self):
        rows=self.rows();rows[0]['acceptance']=['other']
        with self.assertRaises(ValueError):avaliar.aggregate(rows)
    def test_duplicate_rejected(self):
        rows=self.rows();rows.append(rows[0])
        with self.assertRaises(ValueError):avaliar.aggregate(rows)
    def test_split_leak_rejected(self):
        rows=self.rows();r=copy.deepcopy(rows[0]);r.update(split='calibracao',run='another');rows.append(r)
        with self.assertRaises(ValueError):avaliar.aggregate(rows)
    def test_unknown_not_zero(self):
        rows=self.rows();rows[0]['tokens']['input']=None
        with self.assertRaises(ValueError):avaliar.aggregate(rows)
    def test_cost_of_monitor_included(self):
        rows=self.rows();rows[0]['monitor_tokens']=1000
        with self.assertRaises(ValueError):avaliar.aggregate(rows)

if __name__=='__main__':unittest.main()
