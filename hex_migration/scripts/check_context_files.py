import sys, yaml, glob, re, pathlib
root=pathlib.Path(sys.argv[1])
cfg=yaml.safe_load(open(root/'hex_context.config.yaml')); assert set(cfg)<= {'guides','semanticProjects','evals'}, cfg.keys()
for g in sorted(root.glob('guides/*.md')):
    t=g.read_text(); m=re.match(r'^---\n(.*?)\n---\n',t,re.S); fm=yaml.safe_load(m.group(1))
    assert set(fm)=={'name','description'}, fm; print(g.name,'frontmatter OK')
J={'id','type','criterion','expected','expectedSql','warnOnly','measure'}
N={'id','type','target','tolerancePercentage','absoluteTolerance','outputFormat','strictHeadline','extractionGuidance','warnOnly','measure'}
C={'id','prompt','attempts','rubrics','attachments','threadOptions'}
for f in sorted(root.glob('evals/*.yaml')):
    s=yaml.safe_load(open(f)); assert s['name'] and 1<=len(s['cases'])<=100
    assert set(s)<= {'name','id','cases','modelSelection','caseRunSelection'}
    for c in s['cases']:
        assert C>=set(c) and {'id','prompt','attempts','rubrics'}<=set(c) and 1<=c['attempts']<=5 and 1<=len(c['rubrics'])<=15
        assert any(not r.get('warnOnly') for r in c['rubrics'])
        for r in c['rubrics']:
            ok = N if r['type']=='numeric_value' else J
            assert r['type'] in ('judge_thread','judge_final_answer','numeric_value') and set(r)<=ok, r
            if 'expectedSql' in r: assert set(r['expectedSql'])<= {'sql','dataConnectionId','timeoutSeconds'}
    print(f.name,'eval structure OK')
