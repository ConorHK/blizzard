// Draws nothing; it keeps hidden containers from having one child, which Herdr merges away on save.

import { View, div } from "gpui-kit";

export default class Spacer extends View {
  render() {
    return div();
  }
}
