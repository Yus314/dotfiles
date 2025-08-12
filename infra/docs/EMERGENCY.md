# Emergency Response Procedures

## 🔥 緊急度レベル別対応

### 🔴 CRITICAL: サービス停止
**症状**: 本番サービスが利用不可、DNS解決不可、認証サービス停止

**即座対応（5分以内）**:
```bash
# 1. 最新変更の即座ロールバック
git log --oneline -5                    # 直近変更確認
git revert HEAD --no-edit              # 自動コミットでロールバック
tf apply -auto-approve                 # 緊急適用（確認プロンプトスキップ）

# 2. 復旧状態確認
tf plan                                # No changesが表示されることを確認
```

**継続対応**:
```bash
# 3. サービス状態確認
curl -I https://your-domain.com        # 外部からのアクセス確認
dig your-domain.com                    # DNS解決確認
```

---

### 🟡 HIGH: 設定エラー・部分的障害
**症状**: 特定機能の不具合、パフォーマンス劣化、設定不整合

**対応手順（30分以内）**:
```bash
# 1. 作業中変更の一時退避
git status                             # 変更状況確認
git stash push -m "emergency stash"    # 作業中変更の退避

# 2. 安定状態への復帰
tf plan                                # クリーン状態の確認
tf apply                               # 安定状態への復帰

# 3. 問題分析
git stash show -p                      # 問題のあった変更内容確認
tf plan -detailed-exitcode             # 詳細な差分確認
```

**復旧後対応**:
```bash
# 4. 修正版の準備
git stash pop                          # 変更の復元
# 問題を修正してから再度適用
tf plan && tf apply
```

---

### 🟢 MEDIUM: 計画的な修正が可能
**症状**: 軽微な設定問題、非緊急の改善事項

**対応方針**:
- 通常の変更管理プロセスに従って対応
- 十分な検証時間を確保
- ドキュメント更新も併せて実施

---

## ⚡ 迅速復旧コマンド集

### ワンライナー緊急対応
```bash
# 最新コミットの即座取り消し + 適用
git revert HEAD --no-edit && tf apply -auto-approve

# 強制的な前状態復帰（危険: 未保存変更消失）
git reset --hard HEAD~1 && tf apply -auto-approve

# State lockの強制解除 + プラン確認
tf force-unlock $(tf plan 2>&1 | grep "Lock ID" | cut -d: -f2 | tr -d ' ') && tf plan
```

### 状態確認コマンド
```bash
# インフラ全体の健全性確認
for service in cloudflare github; do
  echo "=== $service ==="
  cd services/$service && tf plan --detailed-exitcode
  cd ../../
done

# 外部サービス接続確認
curl -s -o /dev/null -w "%{http_code}" https://api.cloudflare.com/client/v4/ && echo " - Cloudflare API: OK"
curl -s -o /dev/null -w "%{http_code}" https://api.github.com/ && echo " - GitHub API: OK"
```

---

## 📱 連絡・エスカレーション

### インシデント報告テンプレート
```
🚨 Infrastructure Incident Report

Time: $(date)
Severity: [CRITICAL/HIGH/MEDIUM]
Service: [Cloudflare/GitHub/All]

## Symptoms
- [具体的な症状]
- [影響範囲]

## Actions Taken
- [実行したコマンド]
- [結果]

## Current Status
- [現在の状況]
- [追加対応の必要性]
```

### 段階的エスカレーション
1. **自動復旧試行** (0-15分)
2. **手動緊急対応** (15-30分)
3. **専門家への相談** (30分-1時間)
4. **ベンダーサポート連絡** (1時間以上)

---

## 📝 インシデント後の記録

### Git コミットテンプレート
```bash
# 緊急対応後の記録用コミット
git commit -m "fix(infra): emergency rollback due to ${INCIDENT}

Incident Details:
- Time: $(date)
- Severity: ${SEVERITY}
- Duration: ${DURATION}

Immediate Actions:
- ${ACTION_TAKEN}
- Recovery time: ${RECOVERY_TIME}

Root Cause:
- ${ROOT_CAUSE}

Prevention Measures:
- ${PREVENTION_PLAN}
- Process improvements needed: ${IMPROVEMENTS}

Ref: #incident-$(date +%Y%m%d-%H%M)"
```

### 事後分析チェックリスト
- [ ] インシデントの時系列整理
- [ ] 根本原因の特定
- [ ] 影響範囲の詳細調査
- [ ] 再発防止策の策定
- [ ] 手順・ドキュメントの更新
- [ ] モニタリング・アラート設定の見直し

---

## 🛠️ 復旧後の検証

### インフラ健全性確認
```bash
# 1. 全サービスの状態確認
tf plan    # 全サービスでNo changesを確認

# 2. 外部からのアクセステスト
curl -I https://your-domains.com
nslookup your-domains.com

# 3. 認証フローの確認
tf validate    # SOPS + OCI認証確認

# 4. 履歴の整合性確認
git log --oneline -10    # 最近の変更履歴確認
```

### 監視・アラート確認
```bash
# ログの最終確認
tail -f /var/log/terraform.log    # Terraformログ確認
journalctl -u your-service --since "1 hour ago"    # システムログ確認
```

---

## 🎯 事前準備（平時対応）

### 緊急時連絡先の準備
- インフラ責任者の連絡先
- クラウドプロバイダーサポート窓口
- 関係チームのSlack/Teams連絡先

### 定期訓練
- 月次でロールバック手順の確認
- 四半期でインシデント対応訓練
- 年次で災害復旧テスト

この手順に従うことで、**迅速かつ確実なインシデント対応**を実現できます。
