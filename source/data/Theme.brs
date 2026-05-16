' source/data/Theme.brs

' ===========================================
' Theme Constants
' UI colors, fonts, and styling for Phlex
' ===========================================

function Theme() as Object
    obj = {
        ' Colors
        colors: {
            primary: "#1a1a2e"
            secondary: "#0d0d1a"
            accent: "#0095d5"
            textPrimary: "#FFFFFF"
            textSecondary: "#AAAAAA"
            textError: "#FF4444"
            background: "#0d0d1a"
            surface: "#1a1a2e"
            border: "#2a2a3e"
        }

        ' Fonts
        fonts: {
            largeBold: "font:LargeBoldSystemFont"
            large: "font:LargeSystemFont"
            mediumBold: "font:MediumBoldSystemFont"
            medium: "font:MediumSystemFont"
            small: "font:SmallSystemFont"
        }

        ' Spacing
        spacing: {
            xs: 4
            sm: 8
            md: 16
            lg: 24
            xl: 32
        }

        ' Sizes
        sizes: {
            headerHeight: 100
            footerHeight: 40
            posterWidth: 220
            posterHeight: 330
            buttonHeight: 60
            buttonWidth: 160
            iconSize: 40
        }

        ' Grid
        grid: {
            numColumns: 5
            numRows: 3
            itemSpacing: 20
            basePosterWidth: 220
            basePosterHeight: 330
        }
    }

    return obj
end function