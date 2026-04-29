"""
Next_likely_product.py

Purpose:
    Interactive product recommendation tool powered by association rules
    learned via the Apriori algorithm in If_bought_X_buy_Y.R.

    Run If_bought_X_buy_Y.R first to generate:
        data/processed/association_rules.csv

Usage:
    python scripts/Next_likely_product.py
"""

import pandas as pd
from pathlib import Path
from difflib import get_close_matches

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RULES_PATH = PROJECT_ROOT / "data" / "processed" / "association_rules.csv"


def load_rules(rules_path: Path) -> pd.DataFrame:
    if not rules_path.exists():
        raise FileNotFoundError(
            f"Rules file not found: {rules_path}\n"
            "Run If_bought_X_buy_Y.R first to generate association_rules.csv"
        )
    rules = pd.read_csv(rules_path)
    print(f"Loaded {len(rules):,} association rules.\n")
    return rules


def get_all_products(rules: pd.DataFrame) -> list:
    """Return a deduplicated list of all products that appear in any rule."""
    lhs_products = rules["LHS"].dropna().unique().tolist()
    rhs_products = rules["RHS"].dropna().unique().tolist()
    return list(set(lhs_products + rhs_products))


def find_best_match(query: str, all_products: list):
    """
    Find the best matching product for a user query.
    Strategy:
      1. Exact match (case-insensitive)
      2. Substring match - return shortest product containing the query
      3. Fuzzy match via difflib if no substring match found
    Returns (matched_product, match_type) or (None, "no_match")
    """
    query_upper = query.upper()

    # 1. Exact match
    exact = [p for p in all_products if p.upper() == query_upper]
    if exact:
        return exact[0], "exact"

    # 2. Substring match
    substring = [p for p in all_products if query_upper in p.upper()]
    if substring:
        return sorted(substring, key=len)[0], "substring"

    # 3. Fuzzy match
    fuzzy = get_close_matches(query_upper, [p.upper() for p in all_products],
                              n=1, cutoff=0.5)
    if fuzzy:
        matched = next(p for p in all_products if p.upper() == fuzzy[0])
        return matched, "fuzzy"

    return None, "no_match"


def print_legend(conf: float, lift: float, supp: float) -> None:
    """Print the metric explanation box using the actual scores from rank #1."""
    conf_pct = int(round(conf * 100))
    lift_str = f"{lift:.1f}"
    supp_str = f"{supp * 100:.1f}"

    border = "-" * 76
    print()
    print("  What these scores mean (based on rank #1 result):")
    print(f"  +{border}+")
    print(f"   Conf = {conf:.2f} -> {conf_pct}% of customers who bought the searched product")
    print(f"                        also bought the #1 recommended product")
    print(f"   Lift = {lift_str:<5} -> This pair is bought together {lift_str}x more often than")
    print(f"                        random chance. Lift > 1 means a genuine association.")
    print(f"   Supp = {supp:.3f} -> This pair appeared in {supp_str}% of all UK baskets.")
    print(f"                        Low support is normal for specific niche product pairs.")
    print(f"  +{border}+")
    print()


def recommend(query: str, rules: pd.DataFrame, all_products: list,
              top_n: int = 10) -> None:
    matched_product, match_type = find_best_match(query, all_products)

    if matched_product is None:
        print(f"\n  No products found matching '{query}'.")
        print("  Try a different search term or type 'list' to browse products.\n")
        return

    if match_type == "fuzzy":
        print(f"\n  No exact match found. Closest product: '{matched_product}'")

    # Find rules where matched product is the antecedent (LHS)
    matches = rules[rules["LHS"].str.upper() == matched_product.upper()]

    if matches.empty:
        # Try RHS instead
        matches = rules[rules["RHS"].str.upper() == matched_product.upper()]
        if matches.empty:
            print(f"\n  '{matched_product}' exists but has no association rules.\n")
            return
        print(f"\n  Showing what predicts purchase of '{matched_product}':\n")
        result_col = "LHS"
    else:
        result_col = "RHS"

    matches = matches.sort_values("lift", ascending=False).head(top_n)

    print(f"\n  If a customer buys: {matched_product}")
    print(f"  {'-' * 74}")
    print(f"  {'Rank':<5} {'They are also likely to buy':<45} {'Conf':>6} {'Lift':>6} {'Supp':>6}")
    print(f"  {'-' * 74}")

    for rank, (_, row) in enumerate(matches.iterrows(), 1):
        print(
            f"  {rank:<5} {row[result_col]:<45} "
            f"{row['confidence']:>6.2f} "
            f"{row['lift']:>6.2f} "
            f"{row['support']:>6.3f}"
        )

    # Dynamic legend using top result's actual scores
    top_row = matches.iloc[0]
    print_legend(top_row["confidence"], top_row["lift"], top_row["support"])


def main() -> None:
    print("=" * 78)
    print("  PRODUCT RECOMMENDATION TOOL -- powered by Apriori association rules")
    print("=" * 78)

    rules = load_rules(RULES_PATH)
    all_products = get_all_products(rules)

    print(f"  {len(all_products):,} unique products in rule set.")
    print("  Type part of a product name to get co-purchase recommendations.")
    print("  Type 'top'  -> see the 20 globally strongest rules by lift.")
    print("  Type 'list' -> browse all products containing a keyword.")
    print("  Type 'quit' -> exit.\n")

    while True:
        query = input("Search product: ").strip()

        if not query:
            continue

        if query.lower() == "quit":
            print("Goodbye.")
            break

        if query.lower() == "top":
            top = rules.sort_values("lift", ascending=False).head(20)
            print(f"\n  {'-' * 74}")
            print(f"  {'LHS':<35} {'RHS':<25} {'Conf':>6} {'Lift':>6}")
            print(f"  {'-' * 74}")
            for _, row in top.iterrows():
                print(
                    f"  {row['LHS'][:34]:<35} {row['RHS'][:24]:<25} "
                    f"{row['confidence']:>6.2f} {row['lift']:>6.2f}"
                )
            print()
            continue

        if query.lower() == "list":
            keyword = input("  Enter keyword to browse: ").strip().upper()
            matches = [p for p in all_products if keyword in p.upper()]
            if not matches:
                print(f"  No products found containing '{keyword}'.\n")
            else:
                print(f"\n  Products containing '{keyword}':")
                for p in sorted(matches):
                    print(f"    - {p}")
                print()
            continue

        recommend(query, rules, all_products)


if __name__ == "__main__":
    main()
