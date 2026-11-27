from canadian_buildings.smoke import select_one


def test_select_one_returns_one() -> None:
    assert select_one() == 1
