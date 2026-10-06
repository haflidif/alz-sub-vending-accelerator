from __future__ import annotations

import argparse
import html.parser
import pathlib
import sys
import urllib.parse


class PageParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.images: list[str] = []
        self.edit_links: list[str] = []
        self.heading_one_count = 0
        self.has_language = False
        self.has_main = False
        self.has_title = False
        self.is_redirect = False
        self._in_title = False
        self._title_text: list[str] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        attributes = {name: value for name, value in attrs}
        element_id = attributes.get("id")
        if element_id:
            self.ids.add(element_id)
        if tag == "a" and attributes.get("href"):
            self.links.append(attributes["href"] or "")
            if attributes.get("rel") == "edit":
                self.edit_links.append(attributes["href"] or "")
        if tag == "img" and attributes.get("src"):
            self.images.append(attributes["src"] or "")
        if tag == "h1":
            self.heading_one_count += 1
        if tag == "html" and attributes.get("lang"):
            self.has_language = True
        if tag == "main" and attributes.get("id") == "main-content":
            self.has_main = True
        if tag == "title":
            self._in_title = True
        if tag == "meta" and (attributes.get("http-equiv") or "").lower() == "refresh":
            self.is_redirect = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
            self.has_title = bool("".join(self._title_text).strip())

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._title_text.append(data)


def output_path_for_url(
    output_root: pathlib.Path, url_path: str, base_path: str
) -> pathlib.Path | None:
    decoded_path = urllib.parse.unquote(url_path)
    if decoded_path.startswith(base_path):
        decoded_path = decoded_path[len(base_path) :]
    elif decoded_path.startswith("/"):
        return None

    candidate = output_root / decoded_path.lstrip("/")
    if candidate.is_dir():
        candidate = candidate / "index.html"
    elif candidate.suffix == "":
        candidate = candidate / "index.html"
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_root", type=pathlib.Path)
    parser.add_argument("--base-path", default="/")
    args = parser.parse_args()

    output_root = args.output_root.resolve()
    base_path = "/" + args.base_path.strip("/") + "/"
    pages: dict[pathlib.Path, PageParser] = {}
    errors: list[str] = []

    for html_file in output_root.rglob("*.html"):
        page = PageParser()
        page.feed(html_file.read_text(encoding="utf-8"))
        pages[html_file.resolve()] = page
        relative = html_file.relative_to(output_root)
        if page.is_redirect:
            continue
        if not page.has_language:
            errors.append(f"{relative}: missing html language")
        if not page.has_main:
            errors.append(f"{relative}: missing main-content landmark")
        if not page.has_title:
            errors.append(f"{relative}: missing document title")
        if page.heading_one_count != 1:
            errors.append(
                f"{relative}: expected one h1, found {page.heading_one_count}"
            )
        for edit_link in page.edit_links:
            if any(
                duplicate in edit_link
                for duplicate in ("website/content/content/", "website/website/")
            ) or any(
                marker in edit_link
                for marker in ("C:/", "C%3A/", "/Users/", "/home/")
            ):
                errors.append(f"{relative}: invalid edit link {edit_link}")

    for source_file, page in pages.items():
        if page.is_redirect:
            continue
        for src in page.images:
            parsed = urllib.parse.urlsplit(src)
            if parsed.scheme or parsed.netloc or src.startswith("data:"):
                continue
            current_url = "/" + source_file.relative_to(output_root).as_posix()
            if current_url.endswith("index.html"):
                current_url = current_url[: -len("index.html")]
            resolved_url = urllib.parse.urljoin(current_url, parsed.path)
            target_file = output_path_for_url(output_root, resolved_url, base_path)
            if target_file is not None and not target_file.exists():
                errors.append(
                    f"{source_file.relative_to(output_root)}: broken image {src}"
                )

        for href in page.links:
            parsed = urllib.parse.urlsplit(href)
            if parsed.scheme or parsed.netloc or href.startswith(("mailto:", "tel:")):
                continue
            if href.startswith("#"):
                target_file = source_file
            else:
                current_url = "/" + source_file.relative_to(output_root).as_posix()
                if current_url.endswith("index.html"):
                    current_url = current_url[: -len("index.html")]
                resolved_url = urllib.parse.urljoin(current_url, parsed.path)
                target_file = output_path_for_url(output_root, resolved_url, base_path)
                if target_file is None:
                    continue

            if parsed.path and target_file not in pages:
                errors.append(
                    f"{source_file.relative_to(output_root)}: broken link {href}"
                )
                continue
            if parsed.fragment and parsed.fragment not in pages[target_file].ids:
                errors.append(
                    f"{source_file.relative_to(output_root)}: missing fragment {href}"
                )

    if errors:
        print("\n".join(sorted(set(errors))), file=sys.stderr)
        return 1

    print(f"Validated {len(pages)} generated HTML pages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
